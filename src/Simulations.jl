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
        (is_reference_method(m) && !(m in _WARNED_REFERENCE_NAMES)) || continue
        push!(_WARNED_REFERENCE_NAMES, m)   # (once per name and session: frontends generate tasks often)
        if haskey(get(config.methods, m, ParamDict()), :sim_func_name)
            @warn "Method :$m has its own :sim_func_name, but its name marks it as a reference method " *
                  "(see `is_reference_method`), so it is not run. Rename it to run it."
        else
            @info "Method :$m isn't run: its name marks it as a reference method (see `is_reference_method`)."
        end
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
    joint_sweep(key => values, key => values, ...) -> Pair

A sweep of several parameters together (zipped, not a Cartesian product): the `i`-th run sets every parameter to its
`i`-th value, e.g. a grid size with a cell width that follows it:

```julia
Ns = [40, 80, 160]
create_varied_dict(joint_sweep(:Grid_Ns__1 => Ns, :IC_cell => 6 ./ Ns), :PDE_epsilon => [1e-2, 1e-3])
```

Returns the entry for a [`VariedDict`](@ref): a key naming the parameters joined by `&`
(`Symbol("Grid_Ns__1&IC_cell")`; each may address tuple entries, see [`generate_method_tasks`](@ref)) with tuples of
their values (`[(40, 0.15), (80, 0.075), (160, 0.0375)]`), so it is stored and written like any other sweep. A run
has the same parameters (and hash) as a run of a configuration with these values set, so stored results are found
again. The other swept parameters form the Cartesian product with the joint sweep as one dimension.
"""
function joint_sweep(pairs::Pair...)
    length(pairs) >= 2 || throw(ArgumentError("joint_sweep: give at least two parameters (key => values)"))
    names = Symbol[Symbol(first(p)) for p in pairs]
    bad = filter(k -> occursin('&', String(k)) || isempty(String(k)), names)
    isempty(bad) || throw(ArgumentError("joint_sweep: parameter names can't contain `&` or be empty, got $(repr(bad))"))
    allunique(names) || throw(ArgumentError("joint_sweep: every parameter once, got $(repr(names))"))
    for p in pairs
        last(p) isa Union{AbstractVector, Tuple} ||
            throw(ArgumentError("joint_sweep: the values of :$(first(p)) must be a vector (or range), got $(typeof(last(p)))"))
    end
    vals = [collect(last(p)) for p in pairs]
    n = length(first(vals))
    all(v -> length(v) == n, vals) ||
        throw(ArgumentError("joint_sweep: every parameter needs the same number of values, got $(join(length.(vals), ", "))"))
    return Symbol(join(names, '&')) => [Tuple(v[i] for v in vals) for i in 1:n]
end

# The parameters a joint key sets together (`Symbol("Grid_Ns__1&IC_cell")`, see `joint_sweep`); `nothing` for other keys
function _joint_parts(k::Symbol)
    s = String(k)
    occursin('&', s) || return nothing
    parts = split(s, '&')
    return any(isempty, parts) ? nothing : Symbol.(parts)
end

"""
    generate_method_tasks(base_params, active_keys, active_values; ignore_keys = Symbol[])

Expands one method's parameters over the Cartesian product of `active_values`. Keys of the form
`:Ns__x`/`:Ns__1` (`__y`/`__2`, `__z`/`__3`, `__<n>`) set one entry of the tuple parameter `:Ns`;
`:Ns__xy` (`__xz`, `__yz`, `__xyz`) sets several entries and `:Ns__all` every entry of the tuple to
the same swept value (the result is a `Tuple`; entries past its end are added, gaps filled with `0.0`).
A key that is itself a parameter of `base_params` (e.g. `:dt__1`) is an ordinary key. A key joining parameters with
`&` (`Symbol("Grid_Ns__1&IC_cell")`, see [`joint_sweep`](@ref)) sets all of them from a tuple of values, as one
dimension of the product. Varied keys (or parameters of a joint key) that are absent from `base_params` (or ignored)
are not applied to this method. Throws an `ArgumentError` if a suffix key addresses a parameter that is not a tuple or
vector, or if a value of a joint key is not a tuple with a value for each of its parameters.
Returns `(tasks, grid_indices)`.
"""
function generate_method_tasks(base_params::AbstractDict, active_keys::AbstractVector, active_values::AbstractVector;
                               ignore_keys::AbstractVector = Symbol[])
    length(active_keys) == length(active_values) || throw(ArgumentError("active_keys and active_values must have the same length"))
    base = _to_paramdict(base_params)
    ignore = Symbol[Symbol(k) for k in ignore_keys]

    # (index into the value tuple, entry of a joint key's value (0: the whole value), key)
    varied_std = Tuple{Int, Int, Symbol}[]
    # (index into the value tuple, entry of a joint key's value, base key, tuple entries)
    varied_tup = Tuple{Int, Int, Symbol, Union{Symbol, Vector{Int}}}[]
    for (i, k) in enumerate(Symbol.(active_keys))
        k in ignore && continue
        parts = haskey(base, k) ? nothing : _joint_parts(k)
        if parts !== nothing
            bad = findfirst(v -> !(v isa Union{Tuple, AbstractVector} && length(v) == length(parts)), active_values[i])
            bad === nothing || throw(ArgumentError(
                "the joint sweep :$k sets $(length(parts)) parameters, so each of its values is a tuple of " *
                "$(length(parts)) values; got $(repr(active_values[i][bad])) (see `joint_sweep`)"))
        end
        for (j, pk) in (parts === nothing ? ((0, k),) : enumerate(parts))
            pk in ignore && continue
            base_key, idxs = haskey(base, pk) ? (pk, nothing) : _split_varied_key(pk)
            if idxs === nothing
                push!(varied_std, (i, j, pk))
            elseif !(base_key in ignore)
                push!(varied_tup, (i, j, base_key, idxs))
            end
        end
    end
    value_of(p_vals, i, j) = j == 0 ? p_vals[i] : p_vals[i][j]

    grid = isempty(active_values) ? [()] : collect(Iterators.product(active_values...))
    tasks, grid_indices = ParamDict[], Tuple[]
    for (linear_idx, p_vals) in enumerate(grid)
        task = copy(base)
        for (i, j, k) in varied_std
            haskey(task, k) && (task[k] = value_of(p_vals, i, j))
        end
        if !isempty(varied_tup)
            updates = Dict{Symbol, Vector{Any}}()
            for (i, j, base_key, idxs) in varied_tup
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
                    arr[idx] = value_of(p_vals, i, j)
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
    seen = Dict{String, ParamDict}()
    used = Set{Symbol}()
    for method in methods
        base = method === nothing ? copy(config.shared) : assemble_params(config.shared, config.methods, method)
        ignore = method === nothing ? Symbol[] : get_ignore_keys(config.methods, method)
        for k in vkeys
            k in ignore && continue
            parts = haskey(base, k) ? nothing : _joint_parts(k)
            for pk in something(parts, [k])   # (a joint key is used if one of its parameters is)
                base_key, _ = haskey(base, pk) ? (pk, nothing) : _split_varied_key(pk)
                (haskey(base, base_key) && !(pk in ignore) && !(base_key in ignore)) && (push!(used, k); break)
            end
        end
        method_tasks, _ = generate_method_tasks(base, vkeys, vvals; ignore_keys = ignore)
        for task in method_tasks
            h = _param_hash(task)
            if haskey(seen, h)   # (the same run twice, e.g. from a varied key a method doesn't use; or two runs stored alike)
                isequal(seen[h], task) || throw(ArgumentError(_collision_text(seen[h], task)))
                continue
            end
            seen[h] = task
            push!(tasks, task)
        end
    end
    for k in vkeys
        k in used || @warn "Varied parameter :$k does not appear in the parameters of any active method and is ignored."
    end
    return tasks
end

# Two different tasks whose parameters are stored alike (and so would be one run): which values they differ in
function _collision_text(a::AbstractDict, b::AbstractDict)
    keys_ = sort!([k for k in union(keys(a), keys(b)) if !isequal(get(a, k, nothing), get(b, k, nothing))], by = string)
    diffs = join(("$k: $(repr(get(a, k, nothing))) and $(repr(get(b, k, nothing)))" for k in keys_), "; ")
    return "two runs of this configuration have parameters that are stored alike (the same hash), so they would be " *
           "one run: $diffs. Only data identifies a run (functions are skipped): add an identifier that tells them apart " *
           "(e.g. a name or number, or a label field of the object)."
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
The solver receives a deep copy of the parameters (what it changes, also inside arrays, changes neither `params`
nor the parameters the result is stored under); the result is always stored under the task parameters so it can be
found again. Its `metadata` (which the solver may fill) is saved with it, plus `metadata`
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
    sim_data = Base.invokelatest(sim_func, deepcopy(task_params))
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
        if path !== nothing && _is_current_file(path)
            changed = on_changed !== :ignore && _code_changed(path, params, metadata)
            (!changed || on_changed === :warn) && return (changed ? :changed : :cached, nothing, changed)
        end
        _check_name_free(params)   # (a result that couldn't be saved isn't computed)
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

function _stats_task(params::ParamDict, ref_factory, required::Vector{Symbol}, force_overwrite::Bool, dry_run::Bool,
                     ref_record::AbstractString = "", on_changed::Symbol = :warn)
    try
        path = _find_file(params)
        path === nothing && return (:missing, nothing)
        has_reference = ref_factory !== nothing
        # Statistics evaluated with another reference (or an unknown one) are evaluated again, all of them; with the
        # same reference whose code changed (its file or package version), `on_changed` decides, as for solver results:
        # `:warn` keeps them (`:outdated`), `:recompute` evaluates them again, `:ignore` doesn't look at the file. The
        # statistics of a file always belong to one reference (one record): if some are missing (e.g. newly registered),
        # all of them are evaluated with the current reference (`:refreshed`, reported) rather than mixing references.
        change, _ = has_reference ? _reference_change(path, ref_record; ignore_file = on_changed === :ignore) : (:none, "")
        missing_stats = _needs_stats(path, required, has_reference)
        keep = change === :code && on_changed !== :recompute && !force_overwrite
        keep && !missing_stats && return (:outdated, nothing)
        force = force_overwrite || change !== :none
        (force || missing_stats) || return (:cached, nothing)
        status = keep ? :refreshed : :ran
        dry_run && return (status, nothing)
        sim_data = _load_key(path, "raw")
        ref_func = has_reference ? ref_factory(deepcopy(params)) : nothing   # (a copy, like the solver's: the task stays as it is)
        # Evaluated again, the statistics get the current record: statistics of the earlier evaluation that are no
        # longer registered go (they'd pass for evaluated with it); the ones the solver or a post-processor added stay
        stale = force ? setdiff(jldopen(f -> haskey(f, "evaluated_stats") ? Symbol.(f["evaluated_stats"]) : Symbol[], path, "r"),
                                required) : Symbol[]
        _calculate_all_stats!(sim_data, ref_func, force, true, true; reference = ref_record, drop = stale)
        return (status, nothing)
    catch e
        e isa InterruptException && rethrow()
        @error "Statistics failed for parameters $params" exception = (e, catch_backtrace())
        return (:failed, _error_text(e))
    end
end

# What identifies the reference statistics were evaluated with (stored as "evaluated_reference"): the name of the
# factory, its package's version and the digest of the file that defines it, so a changed reference (another name, or
# its file edited) makes the statistics due again. "" without a reference.
function _reference_record(name, factory)
    factory === nothing && return ""
    parts = ["name=$name"]
    v = _func_version(factory)
    isnothing(v) || push!(parts, "version=$v")
    file = try String(first(methods(factory)).file) catch; "" end
    isfile(file) && push!(parts, "file=" * bytes2hex(open(sha256, file)))
    return join(parts, "; ")
end

# How the reference the statistics of a file were evaluated with differs from `record`: `:none`, `:reference` (another
# reference, or one not recorded: `calculate_all_stats!`, files of 0.6.2 and earlier) or `:code` (the same reference,
# its file or package version changed; with `ignore_file` only the package version counts), and the stored record
function _reference_change(path::AbstractString, record::AbstractString; ignore_file::Bool = false)
    stored = jldopen(path, "r") do file
        haskey(file, "evaluated_reference") && return file["evaluated_reference"]
        return haskey(file, "evaluated_with_reference") && file["evaluated_with_reference"] === true ? "" : nothing
    end
    stored === nothing && return (:none, "")   # (nothing evaluated with a reference)
    stored == record && return (:none, stored)
    isempty(stored) && return (:reference, stored)
    parts(r) = Dict(split(p, "="; limit = 2) for p in split(r, "; ") if occursin("=", p))
    a, b = parts(stored), parts(record)
    get(a, "name", "") == get(b, "name", "") || return (:reference, stored)
    ignore_file && (delete!(a, "file"); delete!(b, "file"))
    return (a == b ? :none : :code, stored)
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
        solution = _solution_digest(sim_data)
        if post_func(sim_data) === true
            # A post-processor adds statistics and metadata; it changes neither the parameters (the data would replace
            # another run) nor the solution (the statistics would describe another one; a different result belongs
            # into the solver). Either fails, and nothing is saved.
            _identity(_normalize_params(sim_data.params)) == _identity(_normalize_params(params)) ||
                error("the post-processor $name changed the parameters of the data (to " *
                      "$(_param_summary(_normalize_params(sim_data.params), Set{Symbol}()))); nothing was saved")
            _solution_digest(sim_data) == solution ||
                error("the post-processor $name changed the solution of the data; post-processors add statistics and " *
                      "metadata (a different result belongs into the solver); nothing was saved")
            # The rewrite keeps the record of evaluated statistics, so the next run doesn't redo them; the metadata the
            # post-processor changed is saved with the data.
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

# The SHA-256 digest of the solution of a dataset: every value of its axes (or times and positions) and of `u`, each
# array with its length (`Base.hash` samples large arrays and would miss a change of a few entries)
function _solution_digest(d::AbstractSimData)
    ctx = SHA.SHA256_CTX()
    arrays = d isa ESimData ? (d.axes..., d.u) : Iterators.flatten(((d.t,), d.x, d.u))   # (Lagrangian: one array per step)
    for a in arrays
        SHA.update!(ctx, reinterpret(UInt8, [length(a)]))
        SHA.update!(ctx, !isbitstype(eltype(a)) ? codeunits(repr(a)) :   # (e.g. BigFloat: its text)
                         reinterpret(UInt8, a isa Array ? vec(a) : collect(a)))
    end
    return SHA.digest!(ctx)
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
  another version of the post-processor, see [`run_all_simulations`](@ref)), `:failed`, `:missing`, `:not_run` (the
  solver failed or returned nothing in pass 1: data stored before is left as it is)), and
  `stats_failed`, `postprocessing_failed` (`params => error message`);
- `files`: the data file of each task (in the order of `tasks`), `nothing` where nothing usable is stored. After a
  run, the files holding the results; after a dry run, the files stored now, i.e. the data the configuration needs
  that is there already (e.g. to copy it with its configuration: `filter(!isnothing, s.files)`);
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
    files::Vector{Union{Nothing, String}} = Union{Nothing, String}[]
end

function Base.show(io::IO, ::MIME"text/plain", s::RunSummary)
    verb = s.dry_run ? "would run" : "ran"
    println(io, "RunSummary", s.dry_run ? " (dry run)" : "", ": ", length(s.tasks), " task(s) in ",
            round(s.elapsed, digits = 2), " s: ", length(s.ran), " ", verb, ", ", length(s.cached), " cached",
            isempty(s.empty) ? "" : ", $(length(s.empty)) without output", isempty(s.failed) ? "" : ", $(length(s.failed)) failed")
    isempty(s.tasks) || length(s.files) != length(s.tasks) ||
        println(io, "  stored: ", count(!isnothing, s.files), " of ", length(s.tasks), " result(s) (files)")
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

const _CHANGED_WARNED = Set{UInt}()   # (stored results of other source code warned about in this session)

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
   `on_changed_sources`: `:warn` keeps them and warns (once per session for the same results and code; the summary
   lists them on every run), `:recompute` runs them again, `:ignore` keeps them silently,
2. with `calculate_stats = true`, evaluates missing statistics using the reference factory
   `config.reference` (`params -> (x -> u_exact)`); statistics that were dropped earlier for lack of
   a reference are evaluated again once a reference is configured, and all of them when another reference is
   configured. Statistics evaluated with the same reference whose code changed (the file defining it, or its
   package's version) are handled by `on_changed_sources` like solver results: `:warn` keeps them and reports them
   as `:outdated`, `:recompute` evaluates them again, `:ignore` only looks at the package version. The statistics
   of a file belong to one reference: if some are missing (e.g. newly registered ones), all of them are evaluated with
   the current reference and reported as `:refreshed`.
   `force_stats = true` recomputes every registered statistic without rerunning the simulations,
3. with `post_process = true`, calls `config.postprocess(data)` for every dataset it hasn't post-processed yet and
   saves the data again when it returns `true`. A post-processor adds statistics (`add_stat!`) and metadata; one that
   changed the data's parameters or its solution fails and nothing is saved (a different result belongs into the
   solver). Each file records the post-processor that ran (its name,
   the source files of the run and its package's version), so it runs once per dataset and post-processor: on new
   data, and for a post-processor of another name. Data post-processed by another version of it (other source files
   or package version; with `on_changed_sources = :ignore` only another package version) is kept and reported as
   `:outdated` with a warning; `force_postprocess = true` runs it on every dataset, also on data it has processed
   already, so a post-processor should be idempotent (files of earlier versions have no record: the first run
   post-processes them).
With `dry_run = true` no solver, statistic or post-processor runs and nothing is written (the `sources` are still
included): the summary lists what would run, and its `files` the data files the configuration needs that are stored
already (`nothing` for those that would be computed), e.g. to copy them together with the configuration.
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
    # (a solver that failed or returned nothing: data stored before, e.g. under `force_overwrite`, is not this run's
    # result, so statistics and post-processing leave it as it is)
    not_run = [r[1] in (:failed, :empty) for r in results]
    @info "Pass 1 finished: $(length(ran)) $(dry_run ? "would run" : "run"), $(length(cached)) cached, " *
          "$(length(empty_)) without output, $(length(failed)) failed."
    if !isempty(changed) && on_changed_sources === :warn
        # (once per session for the same results and code: the summary lists them on every run)
        key = hash((sort!([_param_hash(p) for p in changed]), get(metadata, "sources", nothing)))
        if key in _CHANGED_WARNED
            @debug "$(length(changed)) stored result(s) of other source code kept (warned before)."
        else
            push!(_CHANGED_WARNED, key)
            @warn "$(length(changed)) stored result(s) were made with other source code (other contents of the source " *
                  "files, or another version of the solver's package) and are kept. run_all_simulations(…; " *
                  "on_changed_sources = :recompute) recomputes them, :ignore silences this (said once per session)."
        end
    end

    # --- Pass 2: statistics ---
    stats, stats_failed = Dict{Symbol, Int}(), Pair{ParamDict, String}[]
    if calculate_stats
        @info "Pass 2: $(dry_run ? "checking" : "calculating") statistics..."
        ref_factory = resolve_dynamic_function(config.reference)
        ref_record = _reference_record(config.reference, ref_factory)
        required = sort!(Symbol[k for k in keys(get_stat_registry()) if k !== :Solution])
        progress = Progress(n; desc = "Calculating stats...", enabled = !dry_run)
        for (i, params) in enumerate(tasks)
            # (in a dry run, the tasks that would run would get their statistics and post-processing, too)
            st, err = not_run[i] ? (:not_run, nothing) :
                      dry_run && would_run[i] ? (isempty(required) ? :cached : :ran, nothing) :
                      Base.invokelatest(_stats_task, params, ref_factory, required, force_overwrite || force_stats, dry_run,
                                        ref_record, on_changed_sources)
            stats[st] = get(stats, st, 0) + 1
            st === :failed && push!(stats_failed, params => err)
            next!(progress)
        end
        if get(stats, :outdated, 0) > 0
            @warn "$(stats[:outdated]) dataset(s) have statistics evaluated with another version of the reference " *
                  "$(config.reference) (its file or package changed) and are kept. on_changed_sources = :recompute or " *
                  "force_stats = true evaluates them again."
        end
        if get(stats, :refreshed, 0) > 0
            @warn "$(stats[:refreshed]) dataset(s) had statistics evaluated with another version of the reference " *
                  "$(config.reference) and miss others (e.g. newly registered): all of their statistics " *
                  "$(dry_run ? "would be" : "were") evaluated again with the current reference, so the statistics of a " *
                  "file belong to one reference."
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
            st, err = not_run[i] ? (:not_run, nothing) :
                      dry_run && would_run[i] ? (:ran, nothing) :
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
                         postprocessing_failed = post_failed, elapsed = time() - t_start,
                         files = Union{Nothing, String}[_stored_file(t) for t in tasks])
    @info dry_run ? "Dry run complete." : "Batch simulation run complete!"
    return summary
end

# The data file of `params` that loading would use, or `nothing` (also for a file whose data doesn't load as a dataset
# of this version: the pipeline recomputes it; or that can't be read; nothing is written here)
function _stored_file(params::AbstractDict)
    try
        path = _find_file(params)
        return path !== nothing && _is_current_file(path) ? path : nothing
    catch e
        e isa InterruptException && rethrow()
        return nothing   # (an unreadable file, e.g. truncated: pass 1 reported it)
    end
end

# ==============================================================================
# --- Reference generators ---
# ==============================================================================

function _grid_spacing(axes::Tuple, ::Type{T}) where {T}
    return SVector{length(axes), T}(ntuple(d -> _axis_spacing(first(axes[d]), last(axes[d]), length(axes[d]), T), length(axes)))
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
    return ESimData{D, _nspace(domain), M, T}(params, ref_domain, axes, u, StatDict{M, T}(),
                                              _derived_metadata(Dict{Symbol, Any}(), :reference))
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
    return LSimData{D, DS, M, T}(params, domain, t_vec, fill(points, nt), u, StatDict{M, T}(),
                                 _derived_metadata(Dict{Symbol, Any}(), :reference))
end
