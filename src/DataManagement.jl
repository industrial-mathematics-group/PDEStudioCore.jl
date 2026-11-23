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
# `match_params` (keys may be strings or symbols; values are normalised like stored parameters). Only files at their
# name count (`<hash>.jld2` of the parameters they hold): the files lookups use (see `tidy_sim_data` for the others).
function _files_with_params(match_params::AbstractDict)
    wanted = Dict(Symbol(k) => _normalize_param(v) for (k, v) in match_params)
    matched = Pair{String, Any}[]
    for path in sort!(_data_files(), by = p -> (mtime(p), basename(p)), rev = true)
        h = _filename_hash(basename(path))
        h === nothing && continue
        file_params = _file_params(path)
        file_params isa AbstractDict && calculate_hash(file_params) == h || continue
        all(((k, v),) -> haskey(file_params, k) && isequal(file_params[k], v), wanted) || continue
        push!(matched, path => file_params)
    end
    return matched
end

_param_summary(params, skip) = join(("$k = $(val2str(v))" for (k, v) in sort(collect(params), by = p -> string(first(p)))
                                     if !(Symbol(k) in skip)), ", ")

"""
    find_sim_data(match_params = Dict(); io = stdout, verbose = true)

Lists the data files of the runs whose stored parameters contain all the given key-value pairs, i.e. any subset of a
run's parameters (keys may be strings or symbols; an empty filter lists every run). Only the lightweight `params`
metadata is read. Prints one line per file (most recently written first) with the parameters that were not part of
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
renamed, rewritten or deleted, and every copy is written atomically, so an interrupted import is simply run again.

A run that is stored already is skipped (`overwrite = true` replaces the stored data of the same parameters); a file
of other parameters at its name is never replaced. Of several source files of the same parameters the first (by
path) is imported, the others are reported. Files that can't be read, have no dataset, or were written by
PDEStudioCore 0.4 (file format below 3) are reported and skipped.

To change parameters of stored runs (e.g. drop one that no longer exists), import the data folder itself:
`import_sim_data(joinpath(get_save_path(), "data"); remove_keys = [:obsolete])` stores every run under its new
parameters; the files of the old parameters stay until you delete them ([`delete_sim_data`](@ref)).

# Keywords
- `filter_pairs`: only import runs whose stored parameters contain these exact pairs.
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
    sources = Dict{String, String}()   # destination => the source imported to it here
    for src in paths
        stored = try
            jldopen(src, "r") do f
                _format_version(f) < _FORMAT_VERSION ? :old : haskey(f, "raw") && haskey(f, "params") ? f["params"] : nothing
            end
        catch e
            e isa InterruptException && rethrow()
            @warn "Not imported: $src can't be read" exception = e
            push!(failed, src); continue
        end
        if !(stored isa AbstractDict)
            @warn "Not imported: $src " * (stored === :old ? "was written by PDEStudioCore 0.4, which this version doesn't read" :
                                                           "has no dataset or no parameters")
            push!(failed, src); continue
        end
        old = _normalize_params(stored)
        filter_pairs === nothing ||
            all(((k, v),) -> haskey(old, Symbol(k)) && isequal(old[Symbol(k)], _normalize_param(v)), filter_pairs) || continue
        params = copy(old)
        foreach(k -> delete!(params, k), remove)
        isempty(prompt) || _prompt_param_values!(params, prompt, basename(src))
        params = _normalize_params(params)
        dest = _hash_path(calculate_hash(params), dir)
        if haskey(sources, dest)
            @warn "Not imported: $src holds the parameters of $(sources[dest]), imported before"
            push!(skipped, src); continue
        end
        ispath(dest) && samefile(src, dest) && continue   # (in the store under its name already)
        state = _file_state(dest, params)
        if state === :other || state === :unreadable
            @warn "Not imported: $src. " * sprint(showerror, _name_taken(dest, state))
            push!(failed, src); continue
        elseif state === :same && !overwrite
            @info "Already stored: $src (as $(basename(dest)); `overwrite = true` replaces it)"
            push!(skipped, src); continue
        end
        try
            mkpath(dir)
            if _identity(ParamDict(Symbol(k) => v for (k, v) in stored)) == _identity(params)
                _copy_file(src, dest)   # (stored as it is: a byte copy)
            else   # (other parameters: the data is written again with them)
                raw = _open_data(f -> (r = f["raw"]; r.metadata = _file_metadata(f); r), src)
                empty!(raw.params)
                merge!(raw.params, params)
                _write_sim_file(dest, raw, Dict{String, Any}(), src)
            end
        catch e
            e isa InterruptException && rethrow()
            @warn "Not imported: $src" exception = e
            push!(failed, src); continue
        end
        sources[dest] = src
        push!(imported, src => dest)
    end
    @info "Imported $(length(imported)) run(s) into $dir" *
          (isempty(skipped) ? "" : "; $(length(skipped)) skipped (stored already)") *
          (isempty(failed) ? "" : "; $(length(failed)) file(s) not imported (see above)")
    return imported
end

# Copies a file (the file a link points to) to `dest` atomically: into a temporary file next to it, renamed into place
function _copy_file(src::AbstractString, dest::AbstractString)
    tmp = _tmp_path(dest)
    try
        cp(src, tmp; follow_symlinks = true)
        mv(tmp, dest; force = true)
    catch
        rm(tmp; force = true)
        rethrow()
    end
    return dest
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
