# ==============================================================================
# --- Data health checks, listing, deletion & import ---
# ==============================================================================

function _aggregate_component(iterator)
    min_v, max_v = Inf, -Inf
    sum_v = 0.0
    valid_count, nan_count = 0, 0
    for val in iterator
        if isnan(val)
            nan_count += 1
        else
            min_v = min(min_v, val)
            max_v = max(max_v, val)
            sum_v += val
            valid_count += 1
        end
    end
    valid_count == 0 && return (NaN, NaN, NaN, Float64(nan_count))
    return (Float64(min_v), Float64(max_v), Float64(sum_v / valid_count), Float64(nan_count))   # (Float64 columns, also for BigFloat data)
end

_component_summary(values, M::Int) =
    reduce(vcat, [collect(_aggregate_component(v[c] for v in values)) for c in 1:M])

function _health_frame(times::AbstractVector, rows::Vector{Vector{Float64}}, M::Int)
    columns = Pair{Symbol, Vector{Float64}}[:Time => Float64.(collect(times))]
    names = [Symbol("C$(c)_$(s)") for c in 1:M for s in ("Min", "Max", "Mean", "NaNs")]
    for (j, name) in enumerate(names)
        push!(columns, name => Float64[row[j] for row in rows])
    end
    return DataFrame(columns...)
end

"""
    check_data(data::ESimData; per_step = false)
    check_data(data::LSimData)

Summarises the numerical health of a dataset as a `DataFrame` with the columns `Time`, then
`C<c>_Min`, `C<c>_Max`, `C<c>_Mean`, `C<c>_NaNs` for every component `c`. Eulerian data is
aggregated into a single row (`Time = NaN`) unless `per_step = true`; Lagrangian data gets one row
per time step.
"""
function check_data(data::ESimData{D, DS, M, T}; per_step::Bool = false) where {D, DS, M, T}
    if per_step && has_time(data)
        rows = [_component_summary(selectdim(data.u, D, n), M) for n in 1:size(data.u, D)]
        return _health_frame(data.axes[D], rows, M)
    end
    return _health_frame([NaN], [_component_summary(data.u, M)], M)
end

function check_data(data::LSimData{D, DS, M, T}) where {D, DS, M, T}
    rows = Vector{Float64}[_component_summary(step, M) for step in data.u]
    return _health_frame(data.t, rows, M)
end

# Parameters stored in a data file (the lightweight "params" entry), or `nothing` if they cannot be read.
function _file_params(path::AbstractString)
    try
        return jldopen(f -> haskey(f, "params") ? f["params"] : nothing, path, "r")
    catch e
        @warn "Could not read the parameters of $(basename(path))" exception = e
        return nothing
    end
end

# `path => params` of every run in the store (most recently written first) whose stored parameters contain all pairs of
# `match_params` (keys may be strings or symbols; values are normalised like stored parameters and compared like the
# hash compares them: `1` is not `true` or `1.0`). Only files at their name count (`<hash>.jld2` of the parameters they
# hold): the files lookups use (see `tidy_sim_data` for the others).
function _files_with_params(match_params::AbstractDict)
    matched = Pair{String, Any}[]
    for path in sort!(_data_files(), by = p -> (mtime(p), basename(p)), rev = true)
        h = _filename_hash(basename(path))
        h === nothing && continue
        file_params = _file_params(path)
        file_params isa AbstractDict && calculate_hash(file_params) == h || continue
        _has_pairs(_normalize_params(file_params), match_params) || continue
        push!(matched, path => file_params)
    end
    return matched
end

_param_summary(params, skip) = join(("$k = $(val2str(v))" for (k, v) in sort(collect(params), by = p -> string(first(p)))
                                     if !(Symbol(k) in skip)), ", ")

"""
    find_sim_data(match_params = Dict(); io = stdout, verbose = true)

Lists the data files of the runs whose stored parameters contain all the given key-value pairs, i.e. any subset of a
run's parameters (keys may be strings or symbols; an empty filter lists every run). Values are compared as the hash
tells them apart: `1` matches neither `true` nor `1.0`. Only the lightweight `params` metadata is read. Prints one line per file (most recently written first) with the parameters that were not part of
the filter, and returns the file paths. Files that aren't part of the store (see [`tidy_sim_data`](@ref)) aren't listed.

```julia-repl
julia> find_sim_data(Dict("N" => 100));
2 data files with N = 100:
  3f9a51c0….jld2   cfl = 0.5, scheme = upwind, sim_func_name = :advection_solver_1d
  b02c7e14….jld2   cfl = 0.5, scheme = lax_friedrichs, sim_func_name = :advection_solver_1d
```
"""
function find_sim_data(match_params::AbstractDict = Dict{Symbol, Any}(); io::IO = stdout, verbose::Bool = true)
    matched = _files_with_params(match_params)
    paths = String[first(m) for m in matched]
    verbose || return paths
    n = length(paths)
    filter_str = isempty(match_params) ? "" : " with " * _param_summary(match_params, Set{Symbol}())
    println(io, n, " data file", n == 1 ? "" : "s", filter_str, n == 0 ? "." : ":")
    skip = Set(Symbol(k) for k in keys(match_params))
    for (path, params) in matched
        extra = _param_summary(params, skip)
        println(io, "  ", basename(path), isempty(extra) ? "" : "   " * extra)
    end
    return paths
end

"""
    delete_sim_data(match_params::AbstractDict; dry_run = false)

Deletes every data file whose stored parameters contain all the given key-value pairs (the files
[`find_sim_data`](@ref) lists). Returns the paths of the (would-be) deleted files.
An empty filter is rejected because it would match every file.

```julia-repl
julia> delete_sim_data(Dict(:N => 100, :scheme => "upwind"))
```
"""
function delete_sim_data(match_params::AbstractDict; dry_run::Bool = false)
    isempty(match_params) && throw(ArgumentError("refusing to delete with an empty filter (it would match every file)"))
    matched = String[]
    for (path, _) in _files_with_params(match_params)
        push!(matched, path)
        if dry_run
            @info "Would delete $(basename(path))"
        else
            @warn "Deleting file matching criteria: $(basename(path))"
            rm(path)
        end
    end
    return matched
end

"""
    import_sim_data(source; filter_pairs = nothing, remove_keys = Symbol[], prompt_keys = Symbol[],
                    overwrite = false) -> Vector{Pair{String, String}}

Copies runs into the data folder of the current save path: the `.jld2` file `source`, or every `.jld2` file below the
directory `source` (e.g. the data folder of an earlier PDEStudioCore version or of another machine). The parameters
of each run are normalised again (after removing `remove_keys` and asking for `prompt_keys`) and the run is stored
under their hash, as `data/<hash>.jld2` ([`calculate_hash`](@ref)). The source is only read: nothing in it is moved,
renamed, rewritten or deleted (also with `overwrite = true`, also when it is the data folder itself), and every copy
is written atomically, so an interrupted import is simply run again.

Every source file the filter selects is checked before anything is written: it must hold a dataset (`"raw"`) whose
parameters, kind and shape are those stored in the file, in the file format of PDEStudioCore 0.5 and later. Files that
fail (can't be read, no dataset, written by PDEStudioCore 0.4, …) are reported and skipped. What is installed is a
copy of the source, checked again (also that its parameters are still the ones planned): a source that changed in
between is reported, and its destination is left as it is.

A run that is stored already is skipped (`overwrite = true` replaces the stored data of the same parameters); a stored
file of the same parameters that isn't a usable run (e.g. without its dataset) is replaced, with a message. A file
at the destination is never replaced if it holds other parameters or its parameters can't be read, if it is a
symbolic link (an import neither writes through links nor replaces them), or if it is one of the source files. Of
several source files of the same parameters the first (by path) is imported, the others are reported.

To change parameters of stored runs (e.g. drop one that no longer exists), import the data folder itself:
`import_sim_data(joinpath(get_save_path(), "data"); remove_keys = [:obsolete])` stores every run under its new
parameters; the files of the old parameters stay until you delete them ([`delete_sim_data`](@ref)).

# Keywords
- `filter_pairs`: only import runs whose stored parameters contain these exact pairs (compared as the hash tells
  values apart: `1` matches neither `true` nor `1.0`).
- `remove_keys`: parameter keys to drop.
- `prompt_keys`: interactively ask (in the REPL) for new values of these keys for every run.
- `overwrite`: replace the stored data of the same parameters.

Returns the `source => destination` pairs of the runs it copied.
"""
function import_sim_data(source::AbstractString; filter_pairs = nothing, remove_keys::AbstractVector = Symbol[],
                         prompt_keys::AbstractVector = Symbol[], overwrite::Bool = false)
    paths = if isfile(source)
        [String(source)]
    elseif isdir(source)
        sort!([joinpath(root, f) for (root, _, files) in walkdir(source) for f in files if endswith(f, ".jld2")])
    else
        throw(ArgumentError("import_sim_data: $source is neither a file nor a directory"))
    end
    remove, prompt = Symbol.(remove_keys), Symbol.(prompt_keys)
    dir = _data_dir()
    imported, skipped, failed = Pair{String, String}[], String[], String[]
    # the source files (and the files links among them point to): only read, never written
    inputs = Set{String}(abspath.(paths))
    for p in paths
        r = try realpath(p) catch; nothing end
        r === nothing || push!(inputs, r)
    end
    is_input(dest) = abspath(dest) in inputs || (ispath(dest) && realpath(dest) in inputs)

    # 1. Plan: check every source file and choose its destination (nothing is written yet)
    plan = NamedTuple[]
    for src in paths
        # (the filter on the lightweight parameters first: the dataset of a run it excludes isn't loaded)
        stored = try jldopen(f -> haskey(f, "params") ? f["params"] : nothing, src, "r") catch; nothing end
        filter_pairs === nothing || !(stored isa AbstractDict) || _has_pairs(_normalize_params(stored), filter_pairs) || continue
        problem = _run_problem(src)
        if problem !== nothing
            @warn "Not imported: $src: $problem"
            push!(failed, src); continue
        end
        stored = _file_params(src)
        old = _normalize_params(stored)
        params = copy(old)
        foreach(k -> delete!(params, k), remove)
        isempty(prompt) || _prompt_param_values!(params, prompt, basename(src))
        params = _normalize_params(params)
        push!(plan, (src = src, stored = stored, params = params, dest = _hash_path(calculate_hash(params), dir)))
    end

    # 2. Copies: each source is copied next to its destination first, and that copy (the bytes installed) is checked
    # again, so a source changed since the plan (e.g. during a prompt) is reported instead of installed
    sources = Dict{String, String}()   # destination => the source imported to it here
    for (; src, stored, params, dest) in plan
        if haskey(sources, dest)
            @warn "Not imported: $src holds the parameters of $(sources[dest]), imported before"
            push!(skipped, src); continue
        end
        ispath(dest) && samefile(src, dest) && continue   # (in the store under its name already)
        if islink(dest)
            @warn "Not imported: $src. Its destination $dest is a symbolic link, which an import neither writes " *
                  "through nor replaces; remove the link (its target stays), then import again."
            push!(failed, src); continue
        end
        state = _file_state(dest, params)
        if state === :other || state === :unreadable
            @warn "Not imported: $src. " * sprint(showerror, _name_taken(dest, state))
            push!(failed, src); continue
        end
        problem = state === :same ? _run_problem(dest) : nothing
        if state === :same && problem === nothing && !overwrite
            @info "Already stored: $src (as $(basename(dest)); `overwrite = true` replaces it)"
            push!(skipped, src); continue
        end
        if is_input(dest)
            @warn "Not imported: $src. Its destination $dest is one of the files this import reads, which it never " *
                  "writes (also not with `overwrite = true`)."
            push!(failed, src); continue
        end
        mkpath(dir)
        staged = _tmp_path(dest)
        try
            cp(src, staged; follow_symlinks = true)
            changed = _run_problem(staged)
            changed === nothing && _raw_identity(_file_params(staged)) != _raw_identity(stored) &&
                (changed = "its parameters changed")
            if changed !== nothing
                @warn "Not imported: $src changed since it was checked ($changed); $dest is left as it was"
                push!(failed, src); continue
            end
            problem === nothing || @info "Replacing $dest, which isn't a usable run ($problem), with $src"
            if _raw_identity(stored) == _identity(params)
                mv(staged, dest; force = true)   # (stored as it is: the checked copy)
            else   # (other parameters: the data of the checked copy is written again with them)
                raw = _open_data(f -> (r = f["raw"]; r.metadata = _file_metadata(f); r), staged)
                empty!(raw.params)
                merge!(raw.params, params)
                _write_sim_file(dest, raw, Dict{String, Any}(), staged)
            end
        catch e
            e isa InterruptException && rethrow()
            @warn "Not imported: $src" exception = e
            push!(failed, src); continue
        finally
            rm(staged; force = true)
        end
        sources[dest] = src
        push!(imported, src => dest)
    end
    @info "Imported $(length(imported)) run(s) into $dir" *
          (isempty(skipped) ? "" : "; $(length(skipped)) skipped (stored already)") *
          (isempty(failed) ? "" : "; $(length(failed)) file(s) not imported (see above)")
    return imported
end

# Why the file at `path` isn't a usable run (a text), or `nothing`: it must be in the current file format, with the
# fast metadata, and hold a dataset as "raw" whose parameters, kind and shape are the ones stored next to it. Loads the
# dataset.
function _run_problem(path::AbstractString)
    try
        return jldopen(path, "r") do f
            _format_version(f) >= _FORMAT_VERSION || return "it was written by PDEStudioCore 0.4, which this version doesn't read"
            all(k -> haskey(f, k), ("raw", "native", "shape", "params")) || return "it has no dataset or no fast metadata"
            raw, stored = f["raw"], f["params"]
            raw isa AbstractSimData || return "its \"raw\" entry is no dataset (a $(typeof(raw)))"
            stored isa AbstractDict && _identity(_normalize_params(raw.params)) == _identity(_normalize_params(stored)) ||
                return "its dataset has other parameters than the file"
            (f["native"] === _data_kind(raw) && Tuple(f["shape"]) == _data_shape(raw)) ||
                return "the kind or shape stored in it isn't that of its dataset"
            return nothing
        end
    catch e
        e isa InterruptException && rethrow()
        return "it can't be read ($(sprint(showerror, e)))"
    end
end


function _prompt_param_values!(params::ParamDict, prompt_keys::Vector{Symbol}, name::AbstractString)
    println("\n--- Current parameters of $name ---")
    for (k, v) in sort(collect(params), by = x -> string(x[1]))
        println("  $k => $(val2str(v))")
    end
    println("-" ^ 40)
    for key in prompt_keys
        print("Enter value for '$key' (Julia expression, leave blank to skip): ")
        input = strip(readline())
        if isempty(input)
            @info "  Skipped '$key'."
            continue
        end
        try
            # Interactive input is trusted: evaluate it in the user's target module.
            params[key] = Core.eval(get_target_module(), Meta.parse(input))
            @info "  Set $key = $(params[key])"
        catch e
            @warn "  Failed to evaluate '$input'; '$key' is unchanged." exception = e
        end
    end
    return params
end



"""
    tidy_sim_data(; dry_run = false, min_tmp_age = 3600) -> (temp_files, foreign)

Removes the temporary files of writes that never finished (a process killed while writing) from the data folder, if
they are older than `min_tmp_age` seconds (a running write keeps its temporary file younger), and lists the files
there that aren't part of the store: `.jld2` files under other names than `<hash>.jld2` (e.g. data of earlier
versions or copies), files whose stored parameters have another hash than their name, and files whose parameters
can't be read. Lookups never use them, and they are never deleted here: bring their runs into the store with
[`import_sim_data`](@ref), then delete them yourself.

Returns the paths of the temporary files it removed (with `dry_run = true`: would remove) and of the foreign files.
"""
function tidy_sim_data(; dry_run::Bool = false, min_tmp_age::Real = 3600)
    dir = _data_dir()
    temp_files, foreign = String[], String[]
    isdir(dir) || return (temp_files = temp_files, foreign = foreign)
    for path in _data_files(dir)
        h = _filename_hash(basename(path))
        p = h === nothing ? nothing : _file_params(path)
        p isa AbstractDict && calculate_hash(p) == h || push!(foreign, path)
    end
    now_s = time()
    for f in readdir(dir)
        occursin(r"\.jld2\.\d+_[0-9a-f]+_\d+\.tmp$", f) || continue
        path = joinpath(dir, f)
        now_s - mtime(path) >= min_tmp_age && push!(temp_files, path)
    end
    if !dry_run
        foreach(path -> rm(path; force = true), temp_files)
        isempty(temp_files) || @info "Removed $(length(temp_files)) temporary file(s)."
    end
    isempty(foreign) || @info "$(length(foreign)) file(s) in $dir aren't part of the store (lookups don't use them): " *
                              join(basename.(foreign), ", ")
    return (temp_files = temp_files, foreign = foreign)
end

"""
    sim_data_table(match_params = Dict()) -> DataFrame

One row per stored run whose parameters contain all pairs of `match_params` (as [`find_sim_data`](@ref)), most
recently written first: `file`, `created` (when the data was made, from its provenance), `size_mb`, `kind` (`:eulerian` / `:lagrangian`), `shape`,
`format_version`, `stats` (the available statistics), `postprocessed` (the names of the post-processors that ran, or `missing`),
`wall_time` (seconds the solver took, if recorded), `solver`, then one column per parameter (`missing` where a
run doesn't have it; a parameter named like one of the columns before gets the column `param_<name>`, with more
`param_` prefixes if that is a parameter, too). Only the
lightweight entries of each file are read. Files of PDEStudioCore 0.4 show their file format (below 3) and no
metadata: this version doesn't read them.
"""
function sim_data_table(match_params::AbstractDict = Dict{Symbol, Any}())
    rows = Dict{Symbol, Any}[]
    fixed = [:file, :created, :size_mb, :kind, :shape, :format_version, :stats, :postprocessed, :wall_time, :solver]
    files = collect(_files_with_params(match_params))
    # (a parameter `solver`: column `param_solver`, or `param_param_solver` if a file has a parameter `param_solver`; the
    # names are chosen once for all files, so a column means the same parameter in every row)
    names = Set{Symbol}(Symbol(k) for (_, params) in files for k in keys(params))
    column = Dict{Symbol, Symbol}()
    for key in sort!(collect(names), by = string)
        col = key
        while col in fixed || (col != key && col in names)
            col = Symbol("param_", col)
        end
        column[key] = col
    end
    for (path, params) in files
        row = Dict{Symbol, Any}(:file => basename(path), :size_mb => round(filesize(path) / 2^20, digits = 3))
        row[:created] = missing
        try
            jldopen(path, "r") do f
                row[:kind] = haskey(f, "native") ? f["native"] : missing
                row[:shape] = haskey(f, "shape") ? Tuple(f["shape"]) : missing
                row[:format_version] = _format_version(f)
                row[:stats] = haskey(f, "stat_keys") ? sort!(collect(Symbol, f["stat_keys"])) : missing
                md = _file_metadata(f)
                post = get(md, :postprocessed, nothing)
                row[:postprocessed] = post isa AbstractDict && !isempty(post) ?
                                      join(sort!(string.(collect(keys(post)))), ", ") : missing
                prov = get(md, :provenance, nothing)
                row[:wall_time] = prov isa AbstractDict ? get(prov, :wall_time, missing) : missing
                created = prov isa AbstractDict ? get(prov, :created, nothing) : nothing
                row[:created] = created isa AbstractString ? something(tryparse(DateTime, created), missing) : missing
                row[:solver] = prov isa AbstractDict ? get(prov, :solver, missing) : missing
            end
        catch e   # (a file that can't be read leaves its columns `missing`, the table goes on)
            e isa InterruptException && rethrow()
            @warn "Could not read the metadata of $(basename(path))" exception = e
        end
        for (k, v) in params
            row[column[Symbol(k)]] = v
        end
        push!(rows, row)
    end
    pkeys = sort!(collect(setdiff(union(Set{Symbol}(), (keys(r) for r in rows)...), fixed)), by = string)
    cols = [fixed; pkeys]
    return DataFrame([c => Any[get(r, c, missing) for r in rows] for c in cols])
end
