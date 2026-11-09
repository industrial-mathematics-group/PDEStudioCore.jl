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
    return (Float64(min_v), Float64(max_v), sum_v / valid_count, Float64(nan_count))
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
    rehash_sim_data(target_path; delete_old = true, filter_pairs = nothing, remove_keys = Symbol[], prompt_keys = Symbol[])

Re-normalises the parameters of a `.jld2` file (or of every `.jld2` file below a directory),
recomputes the hash and stores the data under its new name. Use it after renaming or removing
parameters, or after changes to the hashing.

# Keywords
- `delete_old`: remove the old file once the new one has been written. For a symlink only the link is removed
  (with a warning naming its target, which may be shared).
- `filter_pairs`: only process files whose parameters contain these exact pairs.
- `remove_keys`: parameter keys to drop before rehashing.
- `prompt_keys`: interactively ask (in the REPL) for new values of these keys for every file.

Returns a vector of `old_path => new_path` pairs.
"""
function rehash_sim_data(target_path::AbstractString; delete_old::Bool = true, filter_pairs = nothing,
                         remove_keys::AbstractVector = Symbol[], prompt_keys::AbstractVector = Symbol[])
    paths = if isfile(target_path) && endswith(target_path, ".jld2")
        [String(target_path)]
    elseif isdir(target_path)
        [joinpath(root, f) for (root, _, files) in walkdir(target_path) for f in files if endswith(f, ".jld2")]
    else
        @warn "Path is neither a .jld2 file nor a directory: $target_path"
        String[]
    end
    renamed = Pair{String, String}[]
    for path in paths
        result = _rehash_single_file(path, delete_old, filter_pairs, Symbol.(remove_keys), Symbol.(prompt_keys))
        result === nothing || push!(renamed, result)
    end
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

function _rehash_single_file(path::String, delete_old::Bool, filter_pairs, remove_keys::Vector{Symbol},
                             prompt_keys::Vector{Symbol})
    raw = try
        jldopen(f -> haskey(f, "raw") ? f["raw"] : nothing, path, "r")
    catch e
        @warn "Failed to open $(basename(path))" exception = e
        nothing
    end
    raw isa Union{ESimData, LSimData} || return nothing
    params = raw.params

    if filter_pairs !== nothing
        all(((k, v),) -> haskey(params, Symbol(k)) && isequal(params[Symbol(k)], _normalize_param(v)), filter_pairs) ||
            return nothing
    end
    bname = basename(path)
    @info "Processing matched file: $bname"

    for key in remove_keys
        haskey(params, key) || continue
        delete!(params, key)
        @info "  Removed key :$key"
    end
    isempty(prompt_keys) || _prompt_param_values!(params, prompt_keys, bname)

    normalized = _normalize_params(params)
    empty!(params)
    merge!(params, normalized)

    m = match(r"^(.+)_[0-9a-fA-F]{64}\.jld2$", bname)
    stamp = m === nothing ? _timestamp() : m.captures[1]
    new_path = joinpath(dirname(path), "$(stamp)_$(calculate_hash(params)).jld2")
    same_file = abspath(new_path) == abspath(path)
    if !same_file && isfile(new_path)
        @warn "$(basename(new_path)) already exists and is replaced by the rehashed $bname."
    end

    try
        _write_sim_file(new_path, raw, Dict{String, Any}(), path)
    catch e
        @error "Failed to write $(basename(new_path))" exception = e
        return nothing
    end

    if same_file
        @info "Rehashed in place (hash unchanged): $bname"
    elseif delete_old
        # A symlinked file: the rehashed data is a regular file now and only the link is removed. Its target may be
        # shared (e.g. a fetched result linked into several save paths), so it is never deleted here.
        islink(path) && @warn "$bname is a symlink: the rehashed data is written to $(basename(new_path)) and the link " *
            "is removed; its target $(realpath(path)) is not deleted by this rehash of the link. Delete it yourself if " *
            "nothing else uses it."
        rm(path; force = true)
        _invalidate_index!()
        @info "Rehashed and renamed: $bname -> $(basename(new_path))"
    else
        @info "Rehashed copy (old file kept): $bname -> $(basename(new_path))"
    end
    return path => new_path
end

"""
    upgrade_sim_data(target = joinpath(get_save_path(), "data"); dry_run = false) -> Dict{Symbol, Vector{String}}

Brings data files written by earlier PDEStudioCore versions to the current file format (a `.jld2` file or every
`.jld2` file in a directory, not recursively): the metadata the current version keeps next to the data (format
version, kind, shape, axes) is written from the stored data, which itself is not rewritten. The pipeline upgrades
files without any such metadata by itself when it finds them; files of version 0.4 work as they are, and
`upgrade_sim_data` adds what they lack (e.g. the axes [`get_sim_data_info`](@ref) reads without loading the data).
Returns the paths by outcome: `:upgraded`, `:current`, `:unreadable` (their data doesn't load as a dataset of this
version: the pipeline recomputes them). With `dry_run = true` nothing is written, and the files that would be
upgraded are listed under `:upgraded`.
"""
function upgrade_sim_data(target::AbstractString = _data_dir(); dry_run::Bool = false)
    paths = isdir(target) ? [joinpath(target, f) for f in readdir(target) if endswith(f, ".jld2")] :
            isfile(target) && endswith(target, ".jld2") ? [String(target)] :
            throw(ArgumentError("$target is neither a .jld2 file nor a directory"))
    out = Dict{Symbol, Vector{String}}(:upgraded => String[], :current => String[], :unreadable => String[])
    for path in paths
        outcome = try
            if dry_run
                v = jldopen(_format_version, path, "r")
                v >= _FORMAT_VERSION ? :current : _raw_loads(path) ? :upgraded : :unreadable
            else
                _upgrade_file!(path)
            end
        catch e
            @warn "Could not upgrade $(basename(path))" exception = e
            :unreadable
        end
        push!(out[outcome], path)
    end
    return out
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
`format_version`, `stats` (the available statistics), `postprocessed` (the post-processor that ran, or `missing`),
`wall_time` (seconds the solver took, if recorded), `solver`, then one column per parameter (`missing` where a
run doesn't have it; a parameter named like one of the columns before gets the column `param_<name>`). Only the
lightweight metadata of each file is read. Files of format version 0 (without metadata) are not listed:
[`upgrade_sim_data`](@ref) brings them up to date.
"""
function sim_data_table(match_params::AbstractDict = Dict{Symbol, Any}())
    rows = Dict{Symbol, Any}[]
    fixed = [:file, :created, :size_mb, :kind, :shape, :format_version, :stats, :postprocessed, :wall_time, :solver]
    for (path, params) in _files_with_params(match_params)
        row = Dict{Symbol, Any}(:file => basename(path), :size_mb => round(filesize(path) / 2^20, digits = 3))
        stamp = match(r"^(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_\d{3})_", basename(path))
        row[:created] = stamp === nothing ? missing : DateTime(stamp.captures[1], dateformat"yyyy-mm-dd_HH-MM-SS_sss")
        jldopen(path, "r") do f
            row[:kind] = haskey(f, "native") ? f["native"] : missing
            row[:shape] = haskey(f, "shape") ? Tuple(f["shape"]) : missing
            row[:format_version] = _format_version(f)
            row[:stats] = haskey(f, "stat_keys") ? sort!(collect(Symbol, f["stat_keys"])) : missing
            post = haskey(f, "postprocessed") ? f["postprocessed"] : nothing
            row[:postprocessed] = post isa AbstractDict ? get(post, "name", missing) : missing
            prov = haskey(f, "provenance") ? f["provenance"] : nothing
            row[:wall_time] = prov isa AbstractDict ? get(prov, "wall_time", missing) : missing
            row[:solver] = prov isa AbstractDict ? get(prov, "solver", missing) : missing
        end
        for (k, v) in params
            key = Symbol(k)
            row[key in fixed ? Symbol("param_", key) : key] = v   # (a parameter `solver`: column `param_solver`)
        end
        push!(rows, row)
    end
    pkeys = sort!(collect(setdiff(union(Set{Symbol}(), (keys(r) for r in rows)...), fixed)), by = string)
    cols = [fixed; pkeys]
    return DataFrame([c => Any[get(r, c, missing) for r in rows] for c in cols])
end
