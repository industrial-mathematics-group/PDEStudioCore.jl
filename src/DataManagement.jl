# ==============================================================================
# --- Data health checks, deletion & rehashing ---
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

# `path => params` of every data file (newest first) whose stored parameters contain all pairs of
# `match_params` (keys may be strings or symbols; values are normalised like stored parameters).
function _files_with_params(match_params::AbstractDict)
    wanted = Dict(Symbol(k) => _normalize_param(v) for (k, v) in match_params)
    matched = Pair{String, Any}[]
    for path in _sort_newest!(_data_files())
        file_params = _file_params(path)
        file_params === nothing && continue
        all(((k, v),) -> haskey(file_params, k) && isequal(file_params[k], v), wanted) || continue
        push!(matched, path => file_params)
    end
    return matched
end

_param_summary(params, skip) = join(("$k = $(val2str(v))" for (k, v) in sort(collect(params), by = p -> string(first(p)))
                                     if !(Symbol(k) in skip)), ", ")

"""
    find_sim_data(match_params = Dict(); io = stdout, verbose = true)

Lists the data files whose stored parameters contain all the given key-value pairs, i.e. any subset of a
run's parameters (keys may be strings or symbols; an empty filter lists every file). Only the lightweight
`params` metadata is read. Prints one line per file (newest first) with the parameters that were not part
of the filter, and returns the file paths.

```julia-repl
julia> find_sim_data(Dict("N" => 100));
2 data files with N = 100:
  2026-10-21_17-45-00_123_3f9a….jld2   cfl = 0.5, scheme = upwind, sim_func_name = :advection_solver_1d
  2026-10-21_17-44-58_907_b02c….jld2   cfl = 0.5, scheme = lax_friedrichs, sim_func_name = :advection_solver_1d
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
            _invalidate_index!()
        end
    end
    return matched
end

"""
    rehash_sim_data(target_path = joinpath(get_save_path(), "data"); delete_old = true, filter_pairs = nothing,
                    remove_keys = Symbol[], prompt_keys = Symbol[]) -> Vector{Pair{String, String}}

Re-normalises the parameters of a `.jld2` file (or of every `.jld2` file below a directory), recomputes their hash
and stores the data under its new name. Use it after renaming or removing parameters, or to give files of earlier
PDEStudioCore versions (file format 3, 0.5 and 0.6) the names of this version, which aren't found otherwise (see
[`calculate_hash`](@ref)). A file whose parameters stay the same is renamed, not written again.

Every file is read and its new name chosen before anything is moved: a new name is never an existing file (two
files of the same time and hash get distinct names, a counter is appended), and files that take each other's names
are moved in two steps. A file that can't be read (or of PDEStudioCore 0.4, file format below 3, which this version
doesn't read) is reported and left as it is.

# Keywords
- `delete_old`: rename (or, with changed parameters, replace) the old file; `false` keeps it under its old name and
  writes a copy. For a symlink, the link is renamed (rewritten data: a regular file replaces the link; its target
  is never deleted).
- `filter_pairs`: only process files whose parameters contain these exact pairs.
- `remove_keys`: parameter keys to drop before rehashing.
- `prompt_keys`: interactively ask (in the REPL) for new values of these keys for every file.

Returns the `old_path => new_path` pairs of the files it renamed or wrote.
"""
function rehash_sim_data(target_path::AbstractString = _data_dir(); delete_old::Bool = true, filter_pairs = nothing,
                         remove_keys::AbstractVector = Symbol[], prompt_keys::AbstractVector = Symbol[])
    paths = if isfile(target_path) && endswith(target_path, ".jld2")
        [String(target_path)]
    elseif isdir(target_path)
        sort!([joinpath(root, f) for (root, _, files) in walkdir(target_path) for f in files if endswith(f, ".jld2")])
    else
        @warn "Path is neither a .jld2 file nor a directory: $target_path"
        String[]
    end
    remove, prompt = Symbol.(remove_keys), Symbol.(prompt_keys)

    # 1. Plan: the new parameters of every file (nothing is moved yet)
    failed, plan = String[], NamedTuple[]
    for path in paths
        version = try
            jldopen(_format_version, path, "r")
        catch e
            @warn "Failed to open $(basename(path))" exception = e
            push!(failed, path); continue
        end
        if version < _FORMAT_VERSION
            @warn "$(basename(path)) is a file of PDEStudioCore 0.4 (file format $version), which this version doesn't read"
            push!(failed, path); continue
        end
        stored = _file_params(path)
        stored isa AbstractDict || (push!(failed, path); continue)
        old = _normalize_params(stored)
        filter_pairs === nothing ||
            all(((k, v),) -> haskey(old, Symbol(k)) && isequal(old[Symbol(k)], _normalize_param(v)), filter_pairs) || continue
        params = copy(old)
        foreach(k -> delete!(params, k), remove)
        isempty(prompt) || _prompt_param_values!(params, prompt, basename(path))
        params = _normalize_params(params)
        push!(plan, (path = path, params = params, rename = isequal(params, stored)))   # (the stored form unchanged)
    end

    # 2. New names: the time of the old name and the new hash; never an existing file other than one renamed away here
    movable = delete_old ? Set(abspath(j.path) for j in plan) : Set{String}()
    taken, jobs = Set{String}(), NamedTuple[]
    stamp_of(path) = (m = match(r"^(.+?)_[0-9a-f]{64}(?:_\d+)?\.jld2$", basename(path)); m === nothing ? _timestamp() : m.captures[1])
    natural(j) = joinpath(dirname(j.path), "$(stamp_of(j.path))_$(calculate_hash(j.params)).jld2")
    # (files at their name already keep it: they come first)
    for j in sort(plan, by = j -> !(j.rename && abspath(natural(j)) == abspath(j.path)))
        dest, k = natural(j), 1
        stamp, h = stamp_of(j.path), calculate_hash(j.params)
        while abspath(dest) in taken || (ispath(dest) && abspath(dest) != abspath(j.path) && !(abspath(dest) in movable))
            k += 1
            dest = joinpath(dirname(j.path), "$(stamp)_$(h)_$(k).jld2")
        end
        push!(taken, abspath(dest))
        (abspath(dest) == abspath(j.path) && j.rename) && continue   # (name and parameters as they are)
        push!(jobs, merge(j, (dest = dest,)))
    end

    # 3. Moves: the renamed files first step aside (so no new name is a file still in place), then go to their names
    staged = Dict{String, String}()
    if delete_old
        for j in jobs
            tmp = string(j.path, ".rehash.", getpid(), ".tmp")
            mv(j.path, tmp; force = true)
            staged[j.path] = tmp
        end
    end
    renamed = Pair{String, String}[]
    for j in jobs
        src = get(staged, j.path, j.path)
        try
            if j.rename
                delete_old ? mv(src, j.dest) : cp(src, j.dest)
            else
                raw = _open_data(f -> (r = f["raw"]; r.metadata = _file_metadata(f); r), src)
                empty!(raw.params); merge!(raw.params, j.params)
                _write_sim_file(j.dest, raw, Dict{String, Any}(), src)
                islink(src) && @warn "$(basename(j.path)) is a symlink: the rehashed data is written to $(basename(j.dest)) " *
                    "and the link is removed; its target $(realpath(src)) is not deleted."
                delete_old && rm(src; force = true)
            end
            push!(renamed, j.path => j.dest)
            @info "Rehashed: $(basename(j.path)) -> $(basename(j.dest))"
        catch e
            e isa InterruptException && rethrow()
            @warn "Could not rehash $(basename(j.path)); it is left as it was" exception = e
            delete_old && ispath(src) && !ispath(j.path) && mv(src, j.path)
            push!(failed, j.path)
        end
    end
    _invalidate_index!()
    isempty(failed) || @warn "$(length(failed)) file(s) were not rehashed (see above): " * join(basename.(failed), ", ")
    return renamed
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
    tidy_sim_data(; dry_run = false, min_tmp_age = 3600) -> (duplicates, temp_files)

Removes files in the data directory that nothing uses:
- older files of a run stored more than once (e.g. by parallel jobs computing the same parameters): lookups always
  use the newest file of a hash, the older ones only take space;
- temporary files of writes that never finished (a process killed while writing), older than `min_tmp_age`
  seconds (a running write keeps its temporary file younger).
Returns the paths it removed (with `dry_run = true`: would remove).
"""
function tidy_sim_data(; dry_run::Bool = false, min_tmp_age::Real = 3600)
    dir = _data_dir()
    duplicates, temp_files = String[], String[]
    isdir(dir) || return (duplicates = duplicates, temp_files = temp_files)
    for (_, files) in _data_index(fresh = true).by_hash
        length(files) > 1 || continue
        append!(duplicates, _sort_newest!(copy(files))[2:end])
    end
    now_s = time()
    for f in readdir(dir)
        occursin(r"\.jld2\.\d+_[0-9a-f]+_\d+\.tmp$", f) || continue
        path = joinpath(dir, f)
        now_s - mtime(path) >= min_tmp_age && push!(temp_files, path)
    end
    if !dry_run
        for path in (duplicates..., temp_files...)
            rm(path; force = true)
        end
        _invalidate_index!()
        isempty(duplicates) && isempty(temp_files) ||
            @info "Removed $(length(duplicates)) duplicate data file(s) and $(length(temp_files)) temporary file(s)."
    end
    return (duplicates = duplicates, temp_files = temp_files)
end

"""
    sim_data_table(match_params = Dict()) -> DataFrame

One row per stored run whose parameters contain all pairs of `match_params` (as [`find_sim_data`](@ref)), newest
first: `file`, `created` (from the file name), `size_mb`, `kind` (`:eulerian` / `:lagrangian`), `shape`,
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
        stamp = match(r"^(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_\d{3})_", basename(path))
        row[:created] = stamp === nothing ? missing : DateTime(stamp.captures[1], dateformat"yyyy-mm-dd_HH-MM-SS_sss")
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
