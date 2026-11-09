# ==============================================================================
# --- Disk layout, saving & loading ---
# ==============================================================================
#
# data/<timestamp>_<sha256>.jld2
#   "raw"        the native dataset (ESimData or LSimData)
#   "native"     :eulerian | :lagrangian            (fast metadata)
#   "params"     normalised parameters              (fast metadata)
#   "stat_keys"  available statistics (incl. :Solution)
#   "registry"   kept dimensions of every statistic
#   "shape"      size of `u` (Eulerian), (time steps, particles) (Lagrangian)
#   "dim_keys", "time_dim"  the axes of the data (fast metadata; files written before Nov 2026 have none)
#   "evaluated_stats"  statistics already evaluated for this raw data (incl. dropped all-NaN ones)
#   "format_version"   the layout of the file (`_FORMAT_VERSION`; files of 0.4 have none: version 1)
#   "provenance"       how the data was made (versions, host, git commit, solver, wall time; see `_provenance`)
#   "postprocessed"    the post-processor that ran on this raw data (see `run_all_simulations`)
#   "conv_*"     cached conversions ("conv_L", "conv_E_<n1>x<n2>...")

const _ENABLE_CONV_CACHE = Ref{Bool}(false)
# Entries tied to the content of "raw": never carried over when the raw data is rewritten.
const _MANAGED_KEYS = ("raw", "native", "params", "stat_keys", "registry", "shape", "dim_keys", "time_dim",
                       "evaluated_stats", "format_version")
# Entries about how the raw data was made: carried over when the same data is rewritten (statistics,
# post-processing, rehash), replaced when new data is saved (see `_new_data_entries`). Like the managed ones,
# `save_sim_data(...; metadata)` refuses them.
const _RECORD_KEYS = ("provenance", "postprocessed")
const _RESERVED_KEYS = (_MANAGED_KEYS..., _RECORD_KEYS...)

# The layout of the data files: 1 = PDEStudioCore 0.4 (no version entry), 2 = with "format_version", the axes
# ("dim_keys", "time_dim") and the record entries. Files without the fast metadata of version 1 are version 0.
const _FORMAT_VERSION = 2

"""
    enable_cache!(val::Bool)

Toggles whether on-the-fly Eulerian/Lagrangian conversions are cached inside the data file.
"""
enable_cache!(val::Bool) = (_ENABLE_CONV_CACHE[] = val)

"""
    SimFileNotFoundError <: Exception

Thrown when no data file matches the requested parameters (or hash), or a requested key is missing.
"""
struct SimFileNotFoundError <: Exception
    message::String
end
Base.showerror(io::IO, e::SimFileNotFoundError) = print(io, "SimFileNotFoundError: ", e.message)

# Cache key of an Eulerian conversion at a given spacetime resolution.
get_conv_key(res::Tuple) = "conv_E_" * join(res, "x")

"""
    set_save_path!(path::AbstractString)

Sets the root directory for saved data and creates its `data` and `figures` subdirectories.
Returns `true` on success.
"""
function set_save_path!(path::AbstractString)
    abs_path = abspath(path)
    try
        mkpath(joinpath(abs_path, "data"))
        mkpath(joinpath(abs_path, "figures"))
    catch e
        @error "Failed to create the save directory $abs_path" exception = e
        return false
    end
    _SAVE_ROOT_PATH[] = abs_path
    @info "Module save root path set to: $abs_path"
    return true
end

"""
    get_save_path()

Returns the root directory used for saving (defaults to the working directory at load time).
"""
get_save_path() = _SAVE_ROOT_PATH[]

_data_dir() = joinpath(get_save_path(), "data")
_timestamp() = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS_sss")

const _HASH_REGEX = r"(?:^|_)([0-9a-f]{64})(?:_|\.jld2$)"

function _filename_hash(name::AbstractString)
    m = match(_HASH_REGEX, name)
    return m === nothing ? nothing : String(m.captures[1])
end

# --- The index of the data directory -----------------------------------------------------------------------------
# A lookup used to list the whole data directory (about 4 ms with 4500 files, several lookups per task). The index
# lists it once per change: it is rebuilt when the directory's modification time changes, and dropped by every writer
# here. File times come from a coarse clock (a few ms; a second on some file systems), so a change right after a
# listing may leave the time as it was: like git's index, a listing made within `_INDEX_RACY` seconds of the
# directory's last change is not trusted, the next lookup lists again. A file found in it is checked to exist; a
# hash that isn't in it is looked up with a fresh listing, as before, so a missed change (e.g. a file system that
# caches directory times) costs time; the one result it can miss is a newer duplicate of a stored run that another
# process added meanwhile (the older file of the same parameters is found until the directory changes again).
mutable struct _DataIndex
    dir::String
    stamp::Float64     # the directory's modification time
    listed::Float64    # when it was listed
    files::Vector{String}
    by_hash::Dict{String, Vector{String}}
end
const _INDEX = Ref{Union{Nothing, _DataIndex}}(nothing)
const _INDEX_RACY = 1.0
const _INDEX_LOCK = ReentrantLock()   # (the pipeline looks files up from several threads)

_invalidate_index!() = (lock(() -> (_INDEX[] = nothing), _INDEX_LOCK); nothing)

function _data_index(; fresh::Bool = false)
    dir = _data_dir()
    lock(_INDEX_LOCK) do
        idx = _INDEX[]
        stamp = isdir(dir) ? mtime(dir) : -1.0
        if fresh || idx === nothing || idx.dir != dir || idx.stamp != stamp ||
           idx.listed - idx.stamp < _INDEX_RACY
            listed = time()
            files = isdir(dir) ? [joinpath(dir, f) for f in readdir(dir) if endswith(f, ".jld2")] : String[]
            by_hash = Dict{String, Vector{String}}()
            for p in files
                h = _filename_hash(basename(p))
                h === nothing || push!(get!(by_hash, h, String[]), p)
            end
            idx = _INDEX[] = _DataIndex(dir, stamp, listed, files, by_hash)
        end
        return idx
    end
end

_data_files() = copy(_data_index().files)

# (ties of the coarse file clock: the newer name, which starts with the time the file was made)
_sort_newest!(paths::Vector{String}) = sort!(paths, by = p -> (mtime(p), basename(p)), rev = true)

# The files of a hash, newest first
function _files_with_hash(hash_val::AbstractString)
    hit = get(_data_index().by_hash, hash_val, nothing)
    if hit === nothing || !all(isfile, hit)
        hit = get(_data_index(fresh = true).by_hash, hash_val, String[])
    end
    return length(hit) > 1 ? _sort_newest!(copy(hit)) : copy(hit)
end
_param_hash(params::AbstractDict) = calculate_hash(_normalize_params(params))

function _find_file(params::AbstractDict)
    files = _files_with_hash(_param_hash(params))
    return isempty(files) ? nothing : first(files)
end

"""
    get_file_name(params::AbstractDict)

Returns the path of the newest `.jld2` file whose hash matches the (normalised) parameters.
Throws a [`SimFileNotFoundError`](@ref) if there is none.
"""
function get_file_name(params::AbstractDict)
    isdir(_data_dir()) || throw(SimFileNotFoundError("Data directory $(_data_dir()) does not exist."))
    path = _find_file(params)
    path === nothing && throw(SimFileNotFoundError("No file with matching parameters found in $(_data_dir())."))
    return path
end

function _files_matching(prefix::AbstractString)
    clean = lowercase(replace(basename(String(prefix)), r"\.jld2$" => ""))
    isempty(clean) && return String[]
    matches = filter(_data_files()) do path
        h = _filename_hash(basename(path))
        return lowercase(replace(basename(path), r"\.jld2$" => "")) == clean || (h !== nothing && startswith(h, clean))
    end
    return _sort_newest!(matches)
end

_has_key(path::AbstractString, key::AbstractString) = jldopen(file -> haskey(file, key), path, "r")

function _load_key(path::AbstractString, key::AbstractString)
    return jldopen(path, "r") do file
        haskey(file, key) || throw(SimFileNotFoundError("Key '$key' not found in $(basename(path))."))
        return file[key]
    end
end

# A temporary file next to `path`, unique per writer (process, task and time; without touching the global RNG),
# so concurrent writers never share one.
_tmp_path(path::AbstractString) =
    string(path, ".", getpid(), "_", string(objectid(current_task()); base = 16), "_", time_ns(), ".tmp")

# Sets top-level entries of an existing file atomically: the entries are written into a byte copy of the file,
# which is then renamed into place, like every other writer. The other entries are not loaded and stored again
# (that would change entries of types the session hasn't loaded). Does nothing if every entry already has the
# given value (`only_missing = true`: if every key already exists). Replacing an entry leaves its old space in
# the file, so a changed entry grows the file by about its size; the data itself is never rewritten here.
function _update_entries!(path::AbstractString, entries::AbstractDict{String}; only_missing::Bool = false)
    pending = jldopen(path, "r") do file
        filter(((k, v),) -> !haskey(file, k) || (!only_missing && !isequal(file[k], v)), entries)
    end
    isempty(pending) && return nothing
    path = realpath(path)  # replace the file a symlink points to, not the link
    tmp = _tmp_path(path)
    try
        cp(path, tmp)
        jldopen(tmp, "a+") do file
            for (k, v) in pending
                haskey(file, k) && delete!(file, k)
                file[k] = v
            end
        end
        mv(tmp, path; force = true)
    catch
        rm(tmp; force = true)
        rethrow()
    end
    return nothing
end

_append_key!(path::AbstractString, key::AbstractString, value) =
    _update_entries!(path, Dict{String, Any}(key => value); only_missing = true)
_set_key!(path::AbstractString, key::AbstractString, value) = _update_entries!(path, Dict{String, Any}(key => value))

# "shape" identifies the native representation: the size of `u` (Eulerian) or
# (time steps, total particle count) (Lagrangian).
_data_kind(::ESimData) = :eulerian
_data_kind(::LSimData) = :lagrangian
_data_shape(data::ESimData) = size(data.u)
_data_shape(data::LSimData) = (length(data.t), sum(length, data.x; init = 0))

function _write_metadata!(file, data::AbstractSimData)
    file["native"] = _data_kind(data)
    file["params"] = data.params
    file["stat_keys"] = collect(keys(data.stats))
    file["registry"] = data.domain.stat_registry
    file["shape"] = collect(_data_shape(data))
    file["dim_keys"] = collect(data.domain.dim_keys)
    file["time_dim"] = data.domain.time_dim   # (nothing for static data)
    file["format_version"] = _FORMAT_VERSION
    return nothing
end

# The type JLD2 had to reconstruct in a value because it isn't loaded in this session (as a string), or `nothing`:
# the value's own type or a type parameter of it (e.g. the element type of a vector), a type stored as a value
# (`JLD2.UnknownType`), or such a value inside containers that can hold values of any type (`Any[…]`,
# `Dict{Symbol, Any}`, sets, tuples, NamedTuples, pairs, also nested in typed ones such as `Vector{Vector{Any}}`). The
# check runs on every rewrite of the data, so its cost is bounded per entry: at most 10^5 values are visited, at most
# 4 levels deep, and each type is checked once (its name, and whether its elements can hide other types).
const _RECONSTRUCTED = r"(?<![\w.])JLD2\.(Reconstructed|Serialized|UnknownType)"
const _RECONSTRUCTED_VISITS = 10^5

function _reconstructed_type(value, depth::Int = 4,
                             state = (budget = Ref(_RECONSTRUCTED_VISITS), seen = Dict{Any, Union{Nothing, String}}(),
                                      hides = Dict{Any, Bool}()))
    state.budget[] -= 1
    T = value isa Type ? value : typeof(value)   # a type stored as a value comes back as `JLD2.UnknownType{…}`
    found = get!(state.seen, T) do               # (once per type: values of the same type cost a lookup)
        text = string(T)
        occursin(_RECONSTRUCTED, text) ? text : nothing
    end
    found === nothing || return found
    (depth > 0 && state.budget[] > 0) || return nothing
    hides(E) = get!(() -> _may_hide(E), state.hides, E)
    items = value isa AbstractDict ? (hides(keytype(value)) ? Iterators.flatten((k, v) for (k, v) in value) :
                                      hides(valtype(value)) ? values(value) : ()) :
            value isa Pair ? (value.first, value.second) :
            value isa Union{Tuple, NamedTuple} ? value :
            value isa Union{AbstractArray, AbstractSet} && hides(eltype(value)) ? value : ()
    for item in items
        state.budget[] > 0 || break
        found = _reconstructed_type(item, depth - 1, state)
        found === nothing || return found
    end
    return nothing
end
_is_reconstructed(value) = _reconstructed_type(value) !== nothing

# Whether elements of type `T` can be (or contain) values of other types than `T` says: abstract types, and containers
# whose elements can be (checked a few levels down).
function _may_hide(T, depth::Int = 4)
    T isa Type || return false
    isconcretetype(T) || return true
    depth > 0 || return false
    T <: AbstractDict && return _may_hide(keytype(T), depth - 1) || _may_hide(valtype(T), depth - 1)
    T <: Union{AbstractArray, AbstractSet, Pair, Tuple, NamedTuple} &&
        return any(P -> _may_hide(P, depth - 1), T <: Union{AbstractArray, AbstractSet} ? (eltype(T),) : fieldtypes(T))
    return false
end

# Copies an entry (recursively for groups) from one open JLD2 file to another. Entries are loaded and stored
# again, so an entry whose type isn't loaded in this session is stored as JLD2's reconstruction (warned).
function _copy_entry!(dest, src, key::AbstractString)
    value = src[key]
    found = _reconstructed_type(value)
    found === nothing || @warn "Entry '$key' contains a type that isn't loaded in this session ($found); it is " *
        "kept as JLD2's reconstruction. Load the package that defines it before rewriting the data."
    if value isa JLD2.Group
        for sub in keys(value)
            _copy_entry!(dest, src, string(key, "/", sub))
        end
    else
        dest[key] = value
    end
    return nothing
end

# Writes a complete file to a temporary path and renames it into place, so an interrupted write never
# corrupts existing data and rewrites do not grow the file. Entries of `previous` that are not managed
# here (and are not stale conversion caches) are carried over.
function _write_sim_file(path::AbstractString, data::AbstractSimData, metadata::AbstractDict,
                         previous::Union{Nothing, AbstractString})
    path = isfile(path) ? realpath(path) : path  # replace the file a symlink points to, not the link
    tmp = _tmp_path(path)
    try
        jldopen(tmp, "w") do file
            file["raw"] = data
            _write_metadata!(file, data)
            for (k, v) in metadata
                # (`nothing` for a record entry: drop it, also an old one)
                (v === nothing && String(k) in _RECORD_KEYS) || (file[String(k)] = v)
            end
            # a new file always gets a provenance (e.g. one `calculate_all_stats!` writes)
            if (previous === nothing || !isfile(previous)) && !haskey(metadata, "provenance")
                file["provenance"] = _provenance()
            end
            if previous !== nothing && isfile(previous)
                jldopen(previous, "r") do old
                    for k in keys(old)
                        (k in _MANAGED_KEYS || startswith(k, "conv_") || haskey(file, k) ||
                         haskey(metadata, k)) && continue
                        try
                            _copy_entry!(file, old, k)
                        catch e
                            @warn "Could not carry over entry '$k' of $(basename(previous))" exception = e
                        end
                    end
                end
            end
        end
        mv(tmp, path; force = true)
    catch
        rm(tmp; force = true)
        rethrow()
    finally
        _invalidate_index!()
    end
    return path
end

"""
    save_sim_data(sim_data::AbstractSimData; overwrite = false, verbose = true, metadata = Dict())

Saves the dataset under the hash of its (normalised) parameters and returns the file path.
An existing file is only replaced when `overwrite = true` (which also drops stale conversion caches).
Writes are atomic: data is written to a temporary file that is then renamed into place.
Extra `metadata` entries are stored as top-level keys of the file.
New data gets a new provenance and no post-processing record; saving the data stored for its parameters again (e.g.
after [`add_stat!`](@ref)) keeps both.
`sim_data.params` is replaced by its normalised form (see [`get_clean_params`](@ref)), as stored in the file.
"""
function save_sim_data(sim_data::AbstractSimData; overwrite::Bool = false, verbose::Bool = true,
                       metadata::AbstractDict = Dict{String, Any}())
    _check_metadata_keys(metadata)
    entries = Dict{String, Any}(string(k) => v for (k, v) in metadata)
    # New data gets a new provenance and no post-processing record. The same data saved again keeps its provenance,
    # and its record if it still has the statistics of the file (e.g. after `add_stat!`; not a recomputed dataset
    # without what a post-processor added).
    path = overwrite ? _find_file(sim_data.params) : nothing
    same = path !== nothing && try
        _is_native_representation(path, sim_data)
    catch e
        e isa InterruptException && rethrow()
        false
    end
    if !same
        merge!(entries, _new_data_entries())
    elseif !issubset(_stored_stat_keys(path), keys(sim_data.stats))
        entries["postprocessed"] = nothing
    end
    return _save_sim_data(sim_data, overwrite, verbose, entries)
end

function _check_metadata_keys(metadata::AbstractDict)
    for k in keys(metadata)
        key = string(k)
        (key in _RESERVED_KEYS || startswith(key, "conv_")) && throw(ArgumentError(
            "metadata key '$key' is reserved for the data file layout; choose another name"))
    end
    return nothing
end

# The record entries of newly made data: its provenance, and no post-processing yet (an old record is dropped)
_new_data_entries(; kwargs...) = Dict{String, Any}("provenance" => _provenance(; kwargs...), "postprocessed" => nothing)

# --- Provenance ------------------------------------------------------------------------------------------------

"""
    _provenance(; solver = nothing, wall_time = nothing, commit = _git_commit())

How data was made, stored in each data file (`"provenance"`): the versions of PDEStudioCore and Julia, the host, the
time, the number of threads and the git commit of the active project, and for data a solver made, the solver (name,
module, package version) and its wall time in seconds.
"""
function _provenance(; solver = nothing, wall_time = nothing, commit = _git_commit())
    p = Dict{String, Any}("pdestudiocore" => string(pkgversion(@__MODULE__)), "julia" => string(VERSION),
                          "host" => gethostname(), "created" => string(now()), "threads" => Threads.nthreads())
    isnothing(commit) || (p["git_commit"] = commit)
    if !isnothing(solver)
        p["solver"] = _func_name(solver)
        root = _func_package(solver)
        isnothing(root) || (p["solver_module"] = string(nameof(root)))
        v = _func_version(solver)
        isnothing(v) || (p["solver_version"] = v)
    end
    isnothing(wall_time) || (p["wall_time"] = Float64(wall_time))
    return p
end

# The name, the top module and its package version (a string or `nothing`) of a function or callable object; never
# throw (bookkeeping must not discard a result)
_func_name(f) = string(f isa Union{Function, Type} ? (try nameof(f) catch; f end) : try nameof(typeof(f)) catch; typeof(f) end)
_func_package(f) = try Base.moduleroot(f isa Union{Function, Type} ? parentmodule(f) : parentmodule(typeof(f))) catch; nothing end
function _func_version(f)
    root = _func_package(f)
    v = isnothing(root) ? nothing : try pkgversion(root) catch; nothing end
    return isnothing(v) ? nothing : string(v)
end

# The commit checked out in the git repository of `dir` (the active project's folder by default), read from the
# repository's files (no git needed), or `nothing`.
function _git_commit(dir::AbstractString = something(Base.active_project(), joinpath(pwd(), "Project.toml")) |> dirname)
    try
        d = abspath(dir)
        while true
            dotgit = joinpath(d, ".git")
            ispath(dotgit) && return _head_commit(dotgit)
            parent = dirname(d)
            parent == d && return nothing
            d = parent
        end
    catch
        return nothing
    end
end

function _head_commit(dotgit::AbstractString)
    gitdir = isdir(dotgit) ? dotgit : begin   # a worktree or submodule: ".git" is a file "gitdir: <path>"
        line = strip(read(dotgit, String))
        startswith(line, "gitdir:") || return nothing
        p = strip(line[8:end])
        isabspath(p) ? p : normpath(joinpath(dirname(dotgit), p))
    end
    common = isfile(joinpath(gitdir, "commondir")) ?
             normpath(joinpath(gitdir, strip(read(joinpath(gitdir, "commondir"), String)))) : gitdir
    head = strip(read(joinpath(gitdir, "HEAD"), String))
    startswith(head, "ref:") || return occursin(r"^[0-9a-f]{40,64}$", head) ? String(head) : nothing
    ref = strip(head[5:end])
    for root in unique((gitdir, common))
        f = joinpath(root, ref)
        isfile(f) && return String(strip(read(f, String)))
    end
    packed = joinpath(common, "packed-refs")
    if isfile(packed)
        for line in eachline(packed)
            parts = split(line)
            length(parts) == 2 && parts[2] == ref && return String(parts[1])
        end
    end
    return nothing
end

# `save_sim_data` without the check of the metadata keys, so internal callers can write managed entries
# (e.g. "evaluated_stats") in the same atomic write as the data.
function _save_sim_data(sim_data::AbstractSimData, overwrite::Bool, verbose::Bool, metadata::AbstractDict)
    normalized = _normalize_params(sim_data.params)
    empty!(sim_data.params)
    merge!(sim_data.params, normalized)

    hash_val = calculate_hash(sim_data.params)
    existing = _files_with_hash(hash_val)
    if isempty(existing)
        mkpath(_data_dir())
        path = joinpath(_data_dir(), "$(_timestamp())_$(hash_val).jld2")
        _write_sim_file(path, sim_data, metadata, nothing)
        verbose && @info "Saved simulation data to $(basename(path))"
        return path
    end
    path = first(existing)
    if overwrite || !_has_key(path, "raw")
        _write_sim_file(path, sim_data, metadata, path)
        verbose && @info "Saved simulation data to $(basename(path)) (replaced; conversion caches cleared)"
    else
        @debug "'raw' already exists in $(basename(path)); skipping save."
    end
    return path
end
save_sim_data(::NoSimData; kwargs...) = nothing

"""
    load_sim_data(params)
    load_sim_data(params, Val(:raw))
    load_sim_data(params, Val(:eulerian), res)
    load_sim_data(params, Val(:lagrangian))
    load_sim_data(params, kind::Symbol, args...)

Loads the dataset matching `params`. `:raw` returns the native data; `:eulerian` returns a grid at the
spacetime resolution `res` (resampled or scattered from particles if needed); `:lagrangian` returns
particle data (grid nodes become stationary particles). Conversions are computed on the fly and
cached in the file when [`enable_cache!`](@ref) is on.
"""
load_sim_data(params::AbstractDict) = load_sim_data(params, Val(:raw))
load_sim_data(params::AbstractDict, kind::Symbol, args...) = load_sim_data(params, Val(kind), args...)
load_sim_data(params::AbstractDict, ::Val{:raw}) = _load_key(get_file_name(params), "raw")

# The statistics stored with the data of a file (its metadata, without loading the data)
_stored_stat_keys(path::AbstractString) =
    jldopen(f -> haskey(f, "stat_keys") ? Symbol[Symbol(k) for k in f["stat_keys"]] : Symbol[], path, "r")

function _native_and_shape(path::AbstractString)
    return jldopen(path, "r") do file
        (haskey(file, "native") && haskey(file, "shape")) || throw(ArgumentError(
            "$(basename(path)) was written by an older PDEStudioCore version (no \"native\"/\"shape\" metadata). " *
            "Run its configuration again (`run_all_simulations` recomputes outdated files) or delete it."))
        return file["native"], Tuple(file["shape"])
    end
end

# Whether `data` is the dataset stored as "raw" in `path`: the same representation and the same solution (its
# statistics may differ), not a conversion or an exact solution that shares its parameters (and hash).
# Loads the stored solution once for the comparison.
function _is_native_representation(path::AbstractString, data::AbstractSimData)
    native, shape = _native_and_shape(path)
    native === _data_kind(data) || return false
    shape == _data_shape(data) || return false
    return _same_solution(_load_key(path, "raw"), data)
end

"""
    get_sim_data_info(params) -> NamedTuple

Describes the stored dataset of `params` without loading it: `(path, kind, shape, dim_keys, time_dim, n_steps)`,
where `kind` is `:eulerian` or `:lagrangian` (the native representation), `shape` the size of `u` (Eulerian) or
`(time steps, particles)` (Lagrangian), `dim_keys`/`time_dim` the axes (`time_dim` is `nothing` for static data)
and `n_steps` the number of stored time steps (0 for static data). Files written by PDEStudioCore before
November 2026 lack the axes in their metadata: for them the data is loaded on every call to read them (rewriting the
data, e.g. with `rehash_sim_data`, adds them). Throws a [`SimFileNotFoundError`](@ref) if nothing is stored for
`params`, and an `ArgumentError` for files of much older versions (without `"native"`/`"shape"`).
"""
function get_sim_data_info(params::AbstractDict)
    path = get_file_name(params)
    # (one opening, so a concurrent overwrite can't pair the shape of one file with the axes of another)
    kind, shape, dim_keys, time_dim = jldopen(path, "r") do file
        (haskey(file, "native") && haskey(file, "shape")) || throw(ArgumentError(
            "$(basename(path)) was written by an older PDEStudioCore version (no \"native\"/\"shape\" metadata). " *
            "Run its configuration again (`run_all_simulations` recomputes outdated files) or delete it."))
        keys_ = haskey(file, "dim_keys") ? file["dim_keys"] : nothing
        tdim = haskey(file, "time_dim") ? file["time_dim"] : missing   # (not an axis name: falls back)
        file["native"], Tuple(file["shape"]), keys_, tdim
    end
    # The stored axes, if they are what this version writes: distinct names, the time axis last (older files may
    # hold user metadata of the same names; Symbols that look exactly like axes can't be told apart without loading)
    valid = dim_keys isa AbstractVector{Symbol} && allunique(dim_keys) &&
            (time_dim === nothing || (time_dim isa Symbol && !isempty(dim_keys) && last(dim_keys) === time_dim)) &&
            (kind !== :eulerian || length(dim_keys) == length(shape))
    if valid
        dim_keys = Tuple(dim_keys)
    else
        domain = _load_key(path, "raw").domain
        dim_keys, time_dim = domain.dim_keys, domain.time_dim
    end
    n_steps = time_dim === nothing ? 0 : kind === :lagrangian ? shape[1] : shape[end]
    return (path = path, kind = kind, shape = shape, dim_keys = dim_keys, time_dim = time_dim, n_steps = n_steps)
end

_same_solution(a::ESimData, b::ESimData) = isequal(a.axes, b.axes) && isequal(a.u, b.u)
_same_solution(a::LSimData, b::LSimData) = isequal(a.t, b.t) && isequal(a.x, b.x) && isequal(a.u, b.u)
_same_solution(::AbstractSimData, ::AbstractSimData) = false

function load_sim_data(params::AbstractDict, ::Val{:eulerian}, res::Tuple)
    path = get_file_name(params)
    native, shape = _native_and_shape(path)
    native === :eulerian && shape == Tuple(res) && return _load_key(path, "raw")
    key = get_conv_key(res)
    _has_key(path, key) && return _load_key(path, key)

    raw = _load_key(path, "raw")
    @info "Eulerian representation $key not cached; generating it on the fly..."
    conv = raw isa LSimData ? convert_to_eulerian(raw, res) : resample_eulerian(raw, res)
    _ENABLE_CONV_CACHE[] && _append_key!(path, key, conv)
    return conv
end

function load_sim_data(params::AbstractDict, ::Val{:lagrangian})
    path = get_file_name(params)
    native, _ = _native_and_shape(path)
    native === :lagrangian && return _load_key(path, "raw")
    _has_key(path, "conv_L") && return _load_key(path, "conv_L")

    @info "Lagrangian representation not cached; generating it on the fly..."
    conv = convert_to_lagrangian(_load_key(path, "raw"))
    _ENABLE_CONV_CACHE[] && _append_key!(path, "conv_L", conv)
    return conv
end

"""
    load_sim_data(hash_prefix::AbstractString; index = 1, key = nothing)

Loads a file by (a prefix of) its parameter hash or by its file name, newest first. Returns the
`Dict` of all stored entries, or only the entry `key` (e.g. `"raw"`) when given.
"""
function load_sim_data(hash_prefix::AbstractString; index::Int = 1, key::Union{Nothing, AbstractString} = nothing)
    isdir(_data_dir()) || throw(SimFileNotFoundError("Data directory $(_data_dir()) does not exist."))
    files = _files_matching(hash_prefix)
    isempty(files) && throw(SimFileNotFoundError("No files found matching the hash prefix: $hash_prefix"))
    1 <= index <= length(files) || throw(ArgumentError(
        "requested index $index, but only $(length(files)) file(s) match '$hash_prefix'"))
    path = files[index]
    @info "Manual load: $(length(files)) matching file(s); loading index $index: $(basename(path))"
    return key === nothing ? JLD2.load(path) : _load_key(path, String(key))
end

"""
    list_available_conversions(params::AbstractDict)

Returns the conversion keys cached in the matching file (e.g. `["conv_L", "conv_E_100x50"]`).
"""
function list_available_conversions(params::AbstractDict)
    return jldopen(file -> filter(k -> startswith(k, "conv_"), collect(keys(file))), get_file_name(params), "r")
end

"""
    does_sim_data_exist(params)
    does_sim_data_exist(params, Val(:raw))
    does_sim_data_exist(params, Val(:eulerian), res)
    does_sim_data_exist(params, Val(:lagrangian))

Checks (without loading the data) whether the native dataset, or a representation that can be
loaded without recomputation, exists on disk.
"""
does_sim_data_exist(params::AbstractDict) = does_sim_data_exist(params, Val(:raw))
does_sim_data_exist(params::AbstractDict, kind::Symbol, args...) = does_sim_data_exist(params, Val(kind), args...)

# A file the pipeline can use: native data plus the metadata loading relies on (format version 1 or later). A file
# of version 0 (data without that metadata) is upgraded in place if its data loads; otherwise it counts as
# missing, so the pipeline recomputes (and replaces) it instead of failing on it. (Lookups never write to files of
# version 1: `upgrade_sim_data` brings them to the current version.)
function _is_current_file(path::AbstractString; upgrade::Bool = true)
    ok, has_raw = jldopen(f -> (haskey(f, "raw") && haskey(f, "native") && haskey(f, "shape"), haskey(f, "raw")), path, "r")
    (ok || !has_raw) && return ok
    upgrade || return _raw_loads(path)   # (what an upgrade would find, without writing)
    _upgrade_file!(path) === :upgraded && return true
    @info "$(basename(path)) was written by an older PDEStudioCore version and can't be read; it is recomputed."
    return false
end

# Whether the "raw" entry of a file loads as a dataset of this version
_raw_loads(path::AbstractString) = jldopen(f -> haskey(f, "raw") && (try f["raw"] isa AbstractSimData catch; false end), path, "r")

# The format version of an open data file (see `_FORMAT_VERSION`; a user entry of that name in a file of 0.4, where
# it wasn't reserved, doesn't count)
function _format_version(file)
    v = haskey(file, "format_version") ? file["format_version"] : nothing
    v isa Integer && v >= 2 && haskey(file, "dim_keys") && return Int(v)   # (written by this version)
    return haskey(file, "native") && haskey(file, "shape") ? 1 : 0
end

# Brings a file to the current format version by writing the metadata of its data (the data itself is kept).
# Returns :current, :upgraded, or :unreadable (its data doesn't load as a dataset of this version).
function _upgrade_file!(path::AbstractString)
    version, raw = jldopen(path, "r") do file
        v = _format_version(file)
        v >= _FORMAT_VERSION && return v, nothing
        return v, haskey(file, "raw") ? (try file["raw"] catch; nothing end) : nothing
    end
    version >= _FORMAT_VERSION && return :current
    raw isa AbstractSimData || return :unreadable
    entries = Dict{String, Any}("native" => _data_kind(raw), "params" => raw.params, "stat_keys" => collect(keys(raw.stats)),
                                "registry" => raw.domain.stat_registry, "shape" => collect(_data_shape(raw)),
                                "dim_keys" => collect(raw.domain.dim_keys), "time_dim" => raw.domain.time_dim,
                                "format_version" => _FORMAT_VERSION)
    _update_entries!(path, entries)
    @info "Upgraded $(basename(path)) to file format version $_FORMAT_VERSION."
    return :upgraded
end

function does_sim_data_exist(params::AbstractDict, ::Val{:raw})
    path = _find_file(params)
    return path !== nothing && _is_current_file(path)
end

function does_sim_data_exist(params::AbstractDict, ::Val{:eulerian}, res::Tuple)
    path = _find_file(params)
    (path === nothing || !_is_current_file(path)) && return false
    _has_key(path, get_conv_key(res)) && return true
    native, shape = _native_and_shape(path)
    native === :eulerian || return false
    return shape == Tuple(res)
end

function does_sim_data_exist(params::AbstractDict, ::Val{:lagrangian})
    path = _find_file(params)
    (path === nothing || !_is_current_file(path)) && return false
    native, _ = _native_and_shape(path)
    return _has_key(path, native === :lagrangian ? "raw" : "conv_L")
end
