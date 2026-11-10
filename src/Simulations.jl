# ==============================================================================
# --- Task generation & the batch pipeline ---
# ==============================================================================

const _REFERENCE_KEYWORDS = ("analytic", "reference", "exact", "baseline", "true")

"""
    is_reference_method(m_name::Symbol)

`true` if a word of the method name (split at `_`, `-` and non-alphanumerics) starts with
"analytic", "reference", "exact", "baseline" or "true" (e.g. `:analytic`, `:exact_solution`, but also
`:godunov_exact_riemann`). Reference methods are skipped by [`run_all_simulations`](@ref) (with a
warning if such a method has its own `:sim_func_name`).
"""
function is_reference_method(m_name::Union{Symbol, AbstractString})
    words = split(lowercase(String(m_name)), r"[^a-z0-9]+"; keepempty = false)
    return any(w -> any(k -> startswith(w, k), _REFERENCE_KEYWORDS), words)
end

# Methods named like a reference but with a solver of their own (e.g. `:godunov_exact_riemann`) are most likely
# real methods. They are skipped all the same (frontends rely on the naming rule); warn once per name.
const _WARNED_REFERENCE_NAMES = Set{Symbol}()
function _warn_skipped_solvers(config)
    for m in config.defaults
        (is_reference_method(m) && haskey(get(config.methods, m, ParamDict()), :sim_func_name)) || continue
        m in _WARNED_REFERENCE_NAMES && continue
        push!(_WARNED_REFERENCE_NAMES, m)
        @warn "Method :$m has its own :sim_func_name, but its name marks it as a reference method " *
              "(see `is_reference_method`), so it is not run. Rename it to run it."
    end
    return nothing
end

"""
    get_ignore_keys(methods::AbstractDict, method_name::Symbol)

The shared keys that `method_name` excludes via its `:ignore` entry.
"""
function get_ignore_keys(method_collection::AbstractDict, method_name::Symbol)
    raw_ignore = get(get(method_collection, method_name, ParamDict()), :ignore, Symbol[])
    if raw_ignore isa AbstractVector || raw_ignore isa Tuple
        return Symbol[Symbol(k) for k in raw_ignore]
    elseif raw_ignore isa Union{AbstractString, Symbol}
        return [Symbol(raw_ignore)]
    end
    return Symbol[]
end

"""
    assemble_params(shared::AbstractDict, methods::AbstractDict, method_name::Symbol)

Shared parameters (minus the method's ignored keys) overridden by the method's own parameters.
The `:ignore` entry itself only controls the assembly and is not part of the result (or the hash).
"""
function assemble_params(shared_params::AbstractDict, method_collection::AbstractDict, method_name::Symbol)
    ignore_keys = get_ignore_keys(method_collection, method_name)
    params = ParamDict()
    for (key, val) in shared_params
        Symbol(key) in ignore_keys || (params[Symbol(key)] = val)
    end
    for (key, val) in get(method_collection, method_name, ParamDict())
        Symbol(key) === :ignore && continue
        params[Symbol(key)] = val
    end
    return params
end

const _TUPLE_LETTERS = Dict('x' => 1, 'y' => 2, 'z' => 3)

# Tuple entries addressed by the suffix of a varied key: one entry (`x`/`1`, `y`/`2`, `z`/`3`, `<n>`), several
# entries at once (`xy`, `yz`, `xyz`, …; a sorted `Vector{Int}`) or `:all` (every entry of the tuple).
# Returns `nothing` if the text is not a tuple suffix.
function _tuple_indices(s::AbstractString)
    s == "all" && return :all
    idx = tryparse(Int, s)
    idx !== nothing && return idx >= 1 ? [idx] : nothing
    (isempty(s) || !all(c -> haskey(_TUPLE_LETTERS, c), s)) && return nothing
    return sort!(unique!([_TUPLE_LETTERS[c] for c in s]))
end

# Splits a varied key into (base key, tuple entries); the entries are `nothing` for ordinary keys,
# a `Vector{Int}` or `:all` otherwise (see `_tuple_indices`).
function _split_varied_key(k::Symbol)
    m = match(r"^(.+)__([a-zA-Z0-9]+)$", String(k))
    m === nothing && return (k, nothing)
    idxs = _tuple_indices(m.captures[2])
    return idxs === nothing ? (k, nothing) : (Symbol(m.captures[1]), idxs)
end

"""
    generate_method_tasks(base_params, active_keys, active_values; ignore_keys = Symbol[])

Expands one method's parameters over the Cartesian product of `active_values`. Keys of the form
`:Ns__x`/`:Ns__1` (`__y`/`__2`, `__z`/`__3`, `__<n>`) set one entry of the tuple parameter `:Ns`;
`:Ns__xy` (`__xz`, `__yz`, `__xyz`) sets several entries and `:Ns__all` every entry of the tuple to
the same swept value (the result is a `Tuple`; entries past its end are added, gaps filled with `0.0`).
A key that is itself a parameter of `base_params` (e.g. `:dt__1`) is an ordinary key. Varied keys that are
absent from `base_params` (or ignored) are not applied to this method. Throws an `ArgumentError` if a
suffix key addresses a parameter that is not a tuple or vector.
Returns `(tasks, grid_indices)`.
"""
function generate_method_tasks(base_params::AbstractDict, active_keys::AbstractVector, active_values::AbstractVector;
                               ignore_keys::AbstractVector = Symbol[])
    length(active_keys) == length(active_values) || throw(ArgumentError("active_keys and active_values must have the same length"))
    base = _to_paramdict(base_params)
    ignore = Symbol[Symbol(k) for k in ignore_keys]

    varied_std = Tuple{Int, Symbol}[]       # (index into the value tuple, key)
    varied_tup = Tuple{Int, Symbol, Union{Symbol, Vector{Int}}}[]  # (index into the value tuple, base key, tuple entries)
    for (i, k) in enumerate(Symbol.(active_keys))
        k in ignore && continue
        base_key, idxs = haskey(base, k) ? (k, nothing) : _split_varied_key(k)
        if idxs === nothing
            push!(varied_std, (i, k))
        elseif !(base_key in ignore)
            push!(varied_tup, (i, base_key, idxs))
        end
    end

    grid = isempty(active_values) ? [()] : collect(Iterators.product(active_values...))
    tasks, grid_indices = ParamDict[], Tuple[]
    for (linear_idx, p_vals) in enumerate(grid)
        task = copy(base)
        for (i, k) in varied_std
            haskey(task, k) && (task[k] = p_vals[i])
        end
        if !isempty(varied_tup)
            updates = Dict{Symbol, Vector{Any}}()
            for (i, base_key, idxs) in varied_tup
                haskey(task, base_key) || continue
                value = task[base_key]
                value isa Union{Tuple, AbstractVector} || throw(ArgumentError(
                    "the varied key :$(active_keys[i]) sets entries of :$base_key, but :$base_key = $(repr(value)) " *
                    "is not a tuple or vector; vary :$base_key itself instead"))
                arr = get!(() -> collect(Any, value), updates, base_key)
                for idx in (idxs === :all ? (1:length(arr)) : idxs)
                    while length(arr) < idx
                        push!(arr, 0.0)
                    end
                    arr[idx] = p_vals[i]
                end
            end
            for (base_key, arr) in updates
                task[base_key] = all(x -> x isa Integer && !(x isa Bool), arr) ? Tuple(Int.(arr)) : Tuple(arr)
            end
        end
        push!(tasks, task)
        push!(grid_indices, isempty(active_values) ? () : Tuple(CartesianIndices(grid)[linear_idx]))
    end
    return tasks, grid_indices
end

"""
    generate_tasks(config::SimulationConfig)

All parameter sets [`run_all_simulations`](@ref) would execute (reference methods skipped,
duplicates removed). Handy to load the results of a sweep:
`[load_sim_data(p) for p in generate_tasks(config)]`.
"""
function generate_tasks(config::SimulationConfig)
    vkeys = sort!(collect(keys(config.varied)))
    vvals = Vector[config.varied[k] for k in vkeys]
    for (k, v) in zip(vkeys, vvals)
        isempty(v) && @warn "Varied parameter :$k has no values: the Cartesian product is empty, so no task is generated."
    end
    methods = isempty(config.methods) && isempty(config.defaults) ? Union{Nothing, Symbol}[nothing] :
              Union{Nothing, Symbol}[m for m in config.defaults if !is_reference_method(m)]
    _warn_skipped_solvers(config)

    tasks = ParamDict[]
    seen = Set{String}()
    used = Set{Symbol}()
    for method in methods
        base = method === nothing ? copy(config.shared) : assemble_params(config.shared, config.methods, method)
        ignore = method === nothing ? Symbol[] : get_ignore_keys(config.methods, method)
        for k in vkeys
            base_key, _ = haskey(base, k) ? (k, nothing) : _split_varied_key(k)
            (haskey(base, base_key) && !(k in ignore) && !(base_key in ignore)) && push!(used, k)
        end
        method_tasks, _ = generate_method_tasks(base, vkeys, vvals; ignore_keys = ignore)
        for task in method_tasks
            h = _param_hash(task)
            h in seen && continue
            push!(seen, h)
            push!(tasks, task)
        end
    end
    for k in vkeys
        k in used || @warn "Varied parameter :$k does not appear in the parameters of any active method and is ignored."
    end
    return tasks
end

function _resolve_solver(params::AbstractDict)
    haskey(params, :sim_func_name) || throw(ArgumentError(
        "the parameters contain no :sim_func_name (the name of the solver function)"))
    name = params[:sim_func_name]
    name isa Function && throw(ArgumentError(
        ":sim_func_name must be the *name* of the solver (a Symbol); functions cannot be hashed"))
    f = resolve_dynamic_function(name)
    f === nothing && throw(ArgumentError("could not resolve the solver function `$name`"))
    return f
end

"""
    run_smart_simulation(sim_func, params; force_overwrite = false, metadata = Dict())

Runs `sim_func(params)` unless a dataset for `params` already exists (then returns `NoSimData()`).
The solver receives a copy of the parameters; the result is always stored under the task
parameters so it can be found again. Its `metadata` (which the solver may fill) is saved with it, plus `metadata`
given here and `:provenance` (versions, host, git commit, the solver and the seconds it took; see
[`sim_data_table`](@ref)); a post-processing record of earlier data is dropped. Returns the produced data (or
`NoSimData()`).
"""
function run_smart_simulation(sim_func, params::AbstractDict; force_overwrite::Bool = false,
                              metadata::AbstractDict = Dict{Symbol, Any}())
    !force_overwrite && does_sim_data_exist(params) && return NoSimData()
    task_params = _to_paramdict(params)
    # invokelatest: the solver may have been defined after the caller started (e.g. via `sources`).
    t0 = time()
    sim_data = Base.invokelatest(sim_func, copy(task_params))
    wall_time = time() - t0
    (sim_data === nothing || sim_data isa NoSimData) && return NoSimData()
    sim_data isa AbstractSimData || throw(ArgumentError(
        "the solver must return an AbstractSimData (see `create_sim_data`), got $(typeof(sim_data))"))
    if _param_hash(sim_data.params) != _param_hash(task_params)
        @warn "The solver returned data whose parameters differ from the task parameters; " *
              "storing it under the task parameters so that it can be found again."
        empty!(sim_data.params)
        merge!(sim_data.params, task_params)
    end
    md = sim_data.metadata
    isempty(metadata) || merge!(md, _metadata_dict(metadata))
    md[:provenance] = _provenance(solver = sim_func, wall_time = wall_time)
    delete!(md, :postprocessed)
    _save_sim_data(sim_data, true, false, Dict{String, Any}())
    return sim_data
end

# Pass 1 for one task: (:cached | :changed | :ran | :empty | :failed, error message or nothing). `:changed`: a
# result is stored, but was made with other source code (kept with `on_changed = :warn`; with `:recompute` the task
# runs again and reports `:ran`, `changed` tells the caller).
function _run_task(params::ParamDict, force_overwrite::Bool, metadata::AbstractDict, on_changed::Symbol, dry_run::Bool)
    changed = false
    try
        path = force_overwrite ? nothing : _find_file(params)
        if path !== nothing && _is_current_file(path; upgrade = !dry_run)   # (a dry run writes nothing)
            changed = on_changed !== :ignore && _code_changed(path, params, metadata)
            (!changed || on_changed === :warn) && return (changed ? :changed : :cached, nothing, changed)
        end
        dry_run && return (:ran, nothing, changed)
        result = run_smart_simulation(_resolve_solver(params), params; force_overwrite = true, metadata = metadata)
        return (result isa NoSimData ? :empty : :ran, nothing, changed)
    catch e
        e isa InterruptException && rethrow()
        @error "Simulation failed for parameters $params" exception = (e, catch_backtrace())
        return (:failed, _error_text(e), changed)
    end
end

_error_text(e) = (msg = e isa LoadError ? sprint(showerror, e.error) : sprint(showerror, e); String(first(split(msg, '\n'))))

# Whether the stored result of `params` was made with other source code than the current run: other contents of
# the source files (compared as a set of digests, so moved files don't count; only if both runs list sources), or
# another version of the solver's package (only if both are known).
function _code_changed(path::AbstractString, params::AbstractDict, metadata::AbstractDict)
    stored = jldopen(_file_metadata, path, "r")
    stored_sources = get(stored, :sources, nothing)
    prov = get(stored, :provenance, nothing)
    stored_version = prov isa AbstractDict ? get(prov, :solver_version, nothing) : nothing
    current = get(metadata, "sources", nothing)
    if stored_sources isa AbstractDict && current isa AbstractDict && !isempty(stored_sources) && !isempty(current)
        Set(values(stored_sources)) == Set(values(current)) || return true
    end
    if stored_version !== nothing
        solver = try _resolve_solver(params) catch; nothing end
        v = solver === nothing ? nothing : _func_version(solver)
        v !== nothing && v != stored_version && return true
    end
    return false
end

function _load_sources(sources::AbstractVector{<:AbstractString})
    for file in sources
        path = abspath(file)
        isfile(path) || throw(ArgumentError("source file not found: $path"))
        Base.include(get_target_module(), path)
    end
    return nothing
end

# Always written (possibly empty), so a rerun without sources replaces digests from an earlier run.
function _source_metadata(sources::AbstractVector{<:AbstractString})
    digests = Dict{String, String}(abspath(f) => bytes2hex(open(sha256, abspath(f))) for f in sources)
    return Dict{String, Any}("sources" => digests)
end

function _stats_task(params::ParamDict, ref_factory, required::Vector{Symbol}, force_overwrite::Bool, dry_run::Bool)
    try
        path = _find_file(params)
        path === nothing && return (:missing, nothing)
        has_reference = ref_factory !== nothing
        (force_overwrite || _needs_stats(path, required, has_reference)) || return (:cached, nothing)
        dry_run && return (:ran, nothing)
        sim_data = _load_key(path, "raw")
        ref_func = has_reference ? ref_factory(params) : nothing
        _calculate_all_stats!(sim_data, ref_func, force_overwrite, true, true)
        return (:ran, nothing)
    catch e
        e isa InterruptException && rethrow()
        @error "Statistics failed for parameters $params" exception = (e, catch_backtrace())
        return (:failed, _error_text(e))
    end
end

# What identifies a post-processor in the records of a dataset (`metadata[:postprocessed]`: name => record): its
# name, the source files of the run (their digests) and its package's version. A file with a record of the same name is not
# post-processed again: with the same record it is `:skipped`, with another one (the post-processor changed)
# `:outdated` (applying it again to post-processed data is only right for an idempotent post-processor:
# `force_postprocess`). With `on_changed_sources = :ignore` the sources don't count.
function _postprocess_record(name, post_func, metadata::AbstractDict)
    sources = get(metadata, "sources", Dict{String, String}())
    record = Dict{Symbol, Any}(:sources => sort!(collect(String, values(sources))))
    v = _func_version(post_func)
    isnothing(v) || (record[:version] = v)
    return Symbol(name) => record
end

_without_sources(record::AbstractDict) = filter(p -> Symbol(first(p)) !== :sources, record)

function _post_task(params::ParamDict, post_func, (name, record)::Pair, force::Bool, dry_run::Bool, ignore_sources::Bool)
    try
        path = _find_file(params)
        path === nothing && return (:missing, nothing)
        done = get(jldopen(f -> _file_metadata(f; strict = true), path, "r"), :postprocessed, nothing)
        records = done isa AbstractDict ? Dict{Symbol, Any}(Symbol(k) => v for (k, v) in done) : Dict{Symbol, Any}()
        own = get(records, name, nothing)
        if !force && own isa AbstractDict
            same = ignore_sources ? isequal(_without_sources(own), _without_sources(record)) : isequal(own, record)
            return (same ? :skipped : :outdated, nothing)
        end
        dry_run && return (:ran, nothing)
        records[name] = record
        sim_data = _load_key(path, "raw")   # (with its metadata)
        if post_func(sim_data) === true
            # The rewrite keeps the record of evaluated statistics, so the next run doesn't redo them; the metadata
            # the post-processor changed is saved with the data.
            sim_data.metadata[:postprocessed] = records
            entries = jldopen(f -> haskey(f, "evaluated_stats") ? Dict{String, Any}("evaluated_stats" => f["evaluated_stats"]) :
                                   Dict{String, Any}(), path, "r")
            _save_sim_data(sim_data, true, false, entries)
        else
            _update_metadata!(path, :postprocessed => records)   # (nothing changed: only the record)
        end
        return (:ran, nothing)
    catch e
        e isa InterruptException && rethrow()
        @error "Post-processing failed for parameters $params" exception = (e, catch_backtrace())
        return (:failed, _error_text(e))
    end
end

# Whether a file is missing (or has stale) entries for any of the required statistics. A statistic that
# was evaluated without a reference and dropped (all NaN) is due again once a reference is available.
function _needs_stats(path::AbstractString, required::Vector{Symbol}, has_reference::Bool = false)
    return jldopen(path, "r") do file
        saved = haskey(file, "stat_keys") ? file["stat_keys"] : Symbol[]
        evaluated = haskey(file, "evaluated_stats") ? file["evaluated_stats"] : Symbol[]
        evaluated_with_reference = haskey(file, "evaluated_with_reference") ? file["evaluated_with_reference"] : false
        file_registry = haskey(file, "registry") ? file["registry"] : nothing
        registry = get_stat_registry()
        for k in required
            if k in saved
                # present: stale only if the kept dimensions changed
            elseif k in evaluated
                has_reference && !evaluated_with_reference && return true
            else
                return true
            end
            file_registry === nothing || get(file_registry, k, nothing) == registry[k] || return true
        end
        return false
    end
end

"""
    RunSummary

What [`run_all_simulations`](@ref) did (or, with `dry_run = true`, would do), shown as a short report:
- `tasks`: the parameter sets of the configuration;
- `ran`, `cached`, `empty` (the solver returned nothing), `failed` (`params => error message`): pass 1;
- `changed`: stored results made with other source code (other contents of the source files, or another version of
  the solver's package), kept (`on_changed_sources = :warn`) or recomputed (`:recompute`); empty with `:ignore`;
- `stats`, `postprocessing`: counts per outcome (`:ran`, `:cached` / `:skipped`, `:outdated` (post-processed by
  another version of the post-processor, see [`run_all_simulations`](@ref)), `:failed`, `:missing`), and
  `stats_failed`, `postprocessing_failed` (`params => error message`);
- `elapsed`: seconds; `dry_run`: whether nothing was run.
"""
Base.@kwdef struct RunSummary
    dry_run::Bool = false
    tasks::Vector{ParamDict} = ParamDict[]
    ran::Vector{ParamDict} = ParamDict[]
    cached::Vector{ParamDict} = ParamDict[]
    empty::Vector{ParamDict} = ParamDict[]
    failed::Vector{Pair{ParamDict, String}} = Pair{ParamDict, String}[]
    changed::Vector{ParamDict} = ParamDict[]
    stats::Dict{Symbol, Int} = Dict{Symbol, Int}()
    stats_failed::Vector{Pair{ParamDict, String}} = Pair{ParamDict, String}[]
    postprocessing::Dict{Symbol, Int} = Dict{Symbol, Int}()
    postprocessing_failed::Vector{Pair{ParamDict, String}} = Pair{ParamDict, String}[]
    elapsed::Float64 = 0.0
end

function Base.show(io::IO, ::MIME"text/plain", s::RunSummary)
    verb = s.dry_run ? "would run" : "ran"
    println(io, "RunSummary", s.dry_run ? " (dry run)" : "", ": ", length(s.tasks), " task(s) in ",
            round(s.elapsed, digits = 2), " s: ", length(s.ran), " ", verb, ", ", length(s.cached), " cached",
            isempty(s.empty) ? "" : ", $(length(s.empty)) without output", isempty(s.failed) ? "" : ", $(length(s.failed)) failed")
    isempty(s.changed) || println(io, "  changed code: ", length(s.changed), " stored result(s) made with other source ",
                                  "code (see on_changed_sources)")
    isempty(s.stats) || println(io, "  statistics: ", _counts_text(s.stats, s.dry_run))
    isempty(s.postprocessing) || println(io, "  post-processing: ", _counts_text(s.postprocessing, s.dry_run))
    for (label, list) in (("failed", s.failed), ("statistics failed", s.stats_failed),
                          ("post-processing failed", s.postprocessing_failed))
        for (p, msg) in first(list, 5)
            println(io, "  $label: ", _param_text(p), ": ", first(msg, 120))
        end
        length(list) > 5 && println(io, "  … $(length(list) - 5) more")
    end
end
Base.show(io::IO, s::RunSummary) =
    print(io, "RunSummary(", length(s.tasks), " tasks: ", length(s.ran), " ran, ", length(s.cached), " cached, ",
          length(s.failed), " failed)")

_counts_text(c, dry) = join(("$(v) $(k === :ran && dry ? "would run" : string(k))" for (k, v) in sort!(collect(c)) if v > 0), ", ")
_param_text(p) = join(("$k = $(val2str(v))" for (k, v) in sort!(collect(p), by = x -> string(first(x)))
                       if k !== :sim_func_name), ", ")

"""
    run_all_simulations(config::SimulationConfig; force_overwrite = false, calculate_stats = false,
                        force_stats = false, post_process = true, force_postprocess = false, parallel = false,
                        load_sources = true, on_changed_sources = :warn, dry_run = false) -> RunSummary

Runs the complete pipeline for a [`SimulationConfig`](@ref) and returns a [`RunSummary`](@ref):
0. includes `config.sources` into the target module (with `load_sources = false` the caller has done that
   itself, e.g. PDEStudio, which runs the source copies bundled with an export in place of their originals; their
   digests are stored either way),
1. runs every task of [`generate_tasks`](@ref) whose data is not on disk yet (all of them with
   `force_overwrite`), in parallel over Julia threads with `parallel = true`. Stored results made with other source
   code (other contents of the source files, or another version of the solver's package) are handled by
   `on_changed_sources`: `:warn` keeps them and warns, `:recompute` runs them again, `:ignore` keeps them silently,
2. with `calculate_stats = true`, evaluates missing statistics using the reference factory
   `config.reference` (`params -> (x -> u_exact)`); statistics that were dropped earlier for lack of
   a reference are evaluated again once a reference is configured. `force_stats = true` recomputes
   every registered statistic without rerunning the simulations,
3. with `post_process = true`, calls `config.postprocess(data)` for every dataset it hasn't post-processed yet and
   saves the (modified) data again when it returns `true`. Each file records the post-processor that ran (its name,
   the source files of the run and its package's version), so it runs once per dataset and post-processor: on new
   data, and for a post-processor of another name. Data post-processed by another version of it (other source files
   or package version; with `on_changed_sources = :ignore` only another package version) is kept and reported as
   `:outdated` with a warning; `force_postprocess = true` runs it on every dataset, also on data it has processed
   already, so a post-processor should be idempotent (files of earlier versions have no record: the first run
   post-processes them).
With `dry_run = true` no solver, statistic or post-processor runs and nothing is written (the `sources` are still
included): the summary lists what would run.
Failures of individual tasks are logged, listed in the summary and do not abort the batch.
"""
function run_all_simulations(config::SimulationConfig; force_overwrite::Bool = false, calculate_stats::Bool = false,
                             force_stats::Bool = false, post_process::Bool = true, force_postprocess::Bool = false,
                             parallel::Bool = false, load_sources::Bool = true, on_changed_sources::Symbol = :warn,
                             dry_run::Bool = false)
    on_changed_sources in (:warn, :recompute, :ignore) ||
        throw(ArgumentError("on_changed_sources = :$on_changed_sources: :warn, :recompute or :ignore"))
    t_start = time()
    @info dry_run ? "Planning the simulation pipeline (dry run)." : "Started simulation pipeline."
    load_sources && _load_sources(config.sources)
    tasks = generate_tasks(config)
    n = length(tasks)
    if n == 0
        @info "No numerical simulations to run."
        return RunSummary(dry_run = dry_run, elapsed = time() - t_start)
    end

    # Every per-task call goes through `invokelatest`, so functions defined after this call started
    # (e.g. in `config.sources`, or a stat preset loaded inside a function) are visible.

    # --- Pass 1: simulations ---
    @info "Pass 1: $(dry_run ? "checking" : "executing") $n simulation task(s) (parallel: $parallel)..."
    metadata = _source_metadata(config.sources)
    results = Vector{Any}(undef, n)
    progress = Progress(n; desc = dry_run ? "Checking simulations..." : "Running simulations...", enabled = !dry_run)
    if parallel && !dry_run
        Threads.@threads for i in 1:n
            results[i] = Base.invokelatest(_run_task, tasks[i], force_overwrite, metadata, on_changed_sources, dry_run)
            next!(progress)
        end
    else
        for i in 1:n
            results[i] = Base.invokelatest(_run_task, tasks[i], force_overwrite, metadata, on_changed_sources, dry_run)
            next!(progress)
        end
    end
    pick(st) = ParamDict[tasks[i] for i in 1:n if results[i][1] in st]
    failed = Pair{ParamDict, String}[tasks[i] => results[i][2] for i in 1:n if results[i][1] === :failed]
    changed = ParamDict[tasks[i] for i in 1:n if results[i][3]]
    ran, cached, empty_ = pick((:ran,)), pick((:cached, :changed)), pick((:empty,))
    would_run = [r[1] === :ran for r in results]
    @info "Pass 1 finished: $(length(ran)) $(dry_run ? "would run" : "run"), $(length(cached)) cached, " *
          "$(length(empty_)) without output, $(length(failed)) failed."
    if !isempty(changed) && on_changed_sources === :warn
        @warn "$(length(changed)) stored result(s) were made with other source code (other contents of the source " *
              "files, or another version of the solver's package) and are kept. run_all_simulations(…; " *
              "on_changed_sources = :recompute) recomputes them, :ignore silences this."
    end

    # --- Pass 2: statistics ---
    stats, stats_failed = Dict{Symbol, Int}(), Pair{ParamDict, String}[]
    if calculate_stats
        @info "Pass 2: $(dry_run ? "checking" : "calculating") statistics..."
        ref_factory = resolve_dynamic_function(config.reference)
        required = sort!(Symbol[k for k in keys(get_stat_registry()) if k !== :Solution])
        progress = Progress(n; desc = "Calculating stats...", enabled = !dry_run)
        for (i, params) in enumerate(tasks)
            # (in a dry run, the tasks that would run would get their statistics and post-processing, too)
            st, err = dry_run && would_run[i] ? (isempty(required) ? :cached : :ran, nothing) :
                      Base.invokelatest(_stats_task, params, ref_factory, required, force_overwrite || force_stats, dry_run)
            stats[st] = get(stats, st, 0) + 1
            st === :failed && push!(stats_failed, params => err)
            next!(progress)
        end
    end

    # --- Pass 3: post-processing ---
    post, post_failed = Dict{Symbol, Int}(), Pair{ParamDict, String}[]
    post_func = resolve_dynamic_function(config.postprocess)
    if post_process && post_func !== nothing
        @info "Pass 3: $(dry_run ? "checking" : "custom") post-processing..."
        record = _postprocess_record(config.postprocess, post_func, metadata)
        progress = Progress(n; desc = "Post-processing...", enabled = !dry_run)
        for (i, params) in enumerate(tasks)
            st, err = dry_run && would_run[i] ? (:ran, nothing) :
                      Base.invokelatest(_post_task, params, post_func, record, force_postprocess, dry_run,
                                        on_changed_sources === :ignore)
            post[st] = get(post, st, 0) + 1
            st === :failed && push!(post_failed, params => err)
            next!(progress)
        end
        if get(post, :outdated, 0) > 0
            @warn "$(post[:outdated]) dataset(s) were post-processed by another version of $(config.postprocess) (other " *
                  "source files or package version) and are kept. run_all_simulations(…; force_postprocess = true) " *
                  "applies it again, to data it has processed already: only right for an idempotent post-processor."
        end
    end

    summary = RunSummary(dry_run = dry_run, tasks = tasks, ran = ran, cached = cached, empty = empty_, failed = failed,
                         changed = changed, stats = stats, stats_failed = stats_failed, postprocessing = post,
                         postprocessing_failed = post_failed, elapsed = time() - t_start)
    @info dry_run ? "Dry run complete." : "Batch simulation run complete!"
    return summary
end

# ==============================================================================
# --- Reference generators ---
# ==============================================================================

function _grid_spacing(axes::Tuple, ::Type{T}) where {T}
    return SVector{length(axes), T}(ntuple(d -> length(axes[d]) > 1 ?
        (last(axes[d]) - first(axes[d])) / T(length(axes[d]) - 1) : one(T), length(axes)))
end

"""
    generate_reference_simdata(ref_func, params, template_domain, res, Val(:eulerian))
    generate_reference_simdata(ref_func, params, template_domain, res, Val(:lagrangian))
    generate_reference_simdata(ref_func, params, template_domain, res, kind::Symbol)

Evaluates the exact solution `ref_func(x::SVector{D})` on a uniform grid spanning the bounding box
of `template_domain` with spacetime resolution `res`, as Eulerian data or as stationary particles.
"""
generate_reference_simdata(ref_func, params::AbstractDict, template_domain::DomainInfo, res::Tuple, kind::Symbol) =
    generate_reference_simdata(ref_func, params, template_domain, res, Val(kind))

function generate_reference_simdata(ref_func, params::AbstractDict, template_domain::DomainInfo{D, T}, res::Tuple,
                                    ::Val{:eulerian}) where {D, T}
    res_ = _check_res(res, D)
    axes = ntuple(d -> _linspace(template_domain.mins[d], template_domain.maxs[d], res_[d]), Val(D))
    M = length(ref_func(SVector{D, T}(ntuple(d -> axes[d][1], Val(D)))))
    return _reference_eulerian(ref_func, params, template_domain, axes, Val(M))
end

function _reference_eulerian(ref_func, params, domain::DomainInfo{D, T}, axes::NTuple{D, Vector{T}}, ::Val{M}) where {D, T, M}
    u = Array{SVector{M, T}, D}(undef, map(length, axes))
    Threads.@threads for I in CartesianIndices(u)
        u[I] = _as_svector(ref_func(SVector{D, T}(ntuple(d -> axes[d][I[d]], Val(D)))), Val(M), T)
    end
    ref_domain = _copy_domain(domain; spacing = _grid_spacing(axes, T))
    return ESimData{D, _nspace(domain), M, T}(params, ref_domain, axes, u)
end

function generate_reference_simdata(ref_func, params::AbstractDict, template_domain::DomainInfo{D, T}, res::Tuple,
                                    ::Val{:lagrangian}) where {D, T}
    return _reference_lagrangian(ref_func, params, template_domain, _check_res(res, D), Val(_nspace(template_domain)))
end

function _reference_lagrangian(ref_func, params, domain::DomainInfo{D, T}, res::NTuple{D, Int}, ::Val{DS}) where {D, T, DS}
    s_axes = ntuple(d -> _linspace(domain.mins[d], domain.maxs[d], res[d]), Val(DS))
    points = vec([SVector{DS, T}(ntuple(d -> s_axes[d][I[d]], Val(DS))) for I in CartesianIndices(ntuple(d -> res[d], Val(DS)))])
    t_vec = D > DS ? _linspace(domain.mins[D], domain.maxs[D], res[D]) : T[0]
    first_point = D > DS ? SVector{D, T}(points[1]..., t_vec[1]) : SVector{D, T}(points[1]...)
    M = length(ref_func(first_point))
    spacing = D > DS ? _grid_spacing((s_axes..., t_vec), T) : _grid_spacing(s_axes, T)
    return _reference_particles(ref_func, params, _copy_domain(domain; spacing = spacing), points, t_vec, Val(M))
end

function _reference_particles(ref_func, params, domain::DomainInfo{D, T}, points::Vector{SVector{DS, T}},
                              t_vec::Vector{T}, ::Val{M}) where {D, T, DS, M}
    nt = length(t_vec)
    u = Vector{Vector{SVector{M, T}}}(undef, nt)
    Threads.@threads for n in 1:nt
        tv = t_vec[n]
        u[n] = [_as_svector(ref_func(D > DS ? SVector{D, T}(p..., tv) : SVector{D, T}(p...)), Val(M), T) for p in points]
    end
    return LSimData{D, DS, M, T}(params, domain, t_vec, fill(points, nt), u)
end
