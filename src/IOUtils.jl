# ==============================================================================
# --- Disk layout, saving & loading ---
# ==============================================================================
#
# data/<sha256>.jld2   (one file per run, named by `calculate_hash` of its parameters)
#   "raw"        the native dataset (ESimData or LSimData)
#   "native"     :eulerian | :lagrangian            (fast metadata)
#   "params"     normalised parameters              (fast metadata)
#   "stat_keys"  available statistics (incl. :Solution)
#   "registry"   kept dimensions of every statistic
#   "shape"      size of `u` (Eulerian), (time steps, particles) (Lagrangian)
#   "dim_keys", "time_dim"  the axes of the data (fast metadata)
#   "evaluated_stats"  statistics already evaluated for this raw data (incl. dropped all-NaN ones)
#   "format_version"   the layout of the file (`_FORMAT_VERSION`; checked when files are imported)
#   "metadata"   the dataset's `metadata` field ("raw" is stored without it): provenance, sources, post-processing
#                record, the user's entries
#   "evaluated_with_reference"  whether a reference was available for "evaluated_stats"
#   "evaluated_reference"       which reference that was (`_reference_record`; "" for none or an unknown one)
#   "conv_*"     cached conversions ("conv_L", "conv_E_<n1>x<n2>...")

const _ENABLE_CONV_CACHE = Ref{Bool}(false)
# Entries tied to the content of "raw": never carried over when the raw data is rewritten.
const _MANAGED_KEYS = ("raw", "native", "params", "stat_keys", "registry", "shape", "dim_keys", "time_dim",
                       "evaluated_stats", "format_version", "metadata")

# The layout of the data files: 3 = datasets with the `metadata` field, stored as "metadata" (PDEStudioCore 0.5 and
# later). Files of earlier layouts (0.4: 0 without the fast metadata, 1, 2) aren't read since 0.7.
const _FORMAT_VERSION = 3

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

# --- The store ---------------------------------------------------------------------------------------------------
# One file per run: `data/<hash>.jld2`, the hash of its normalised parameters (`calculate_hash`). There are no
# duplicates by construction, so a lookup is a single path, checked against the parameters stored in the file: a file
# is only ever taken for (and replaced by) the run its name stands for. Files are only ever written to their own name
# (atomically: a temporary file renamed into place); nothing here moves, renames or deletes data on its own (only
# `delete_sim_data` deletes, on request). Files under other names (data of earlier versions, copies) aren't part of
# the store: `import_sim_data` copies them in, `tidy_sim_data` lists them.
const _HASH_NAME = r"^([0-9a-f]{64})\.jld2$"

# The hash a store file name stands for (`nothing` for any other name)
function _filename_hash(name::AbstractString)
    m = match(_HASH_NAME, name)
    return m === nothing ? nothing : String(m.captures[1])
end

_hash_path(hash_val::AbstractString, dir::AbstractString = _data_dir()) = joinpath(dir, hash_val * ".jld2")

# Every `.jld2` file in the data directory (also those under other names), sorted by name
_data_files(dir::AbstractString = _data_dir()) =
    isdir(dir) ? String[joinpath(dir, f) for f in readdir(dir) if endswith(f, ".jld2")] : String[]

_param_hash(params::AbstractDict) = calculate_hash(_normalize_params(params))

# The file of these parameters, or `nothing`: the file named by their hash, if it holds them
_find_file(params::AbstractDict) = (clean = _normalize_params(params); _file_for(clean, calculate_hash(clean)))

# The file named by `hash_val` if it holds the normalised parameters `normalized` (compared by their canonical
# encoding, which tells `true` from `1`), else `nothing`. `fresh = true` reads the file again (before a write).
function _file_for(normalized::AbstractDict, hash_val::AbstractString = calculate_hash(normalized); fresh::Bool = false)
    path = _hash_path(hash_val)
    _stored_identity(path; fresh) == _identity(normalized) || return nothing
    return path
end

# What the file at `path` holds: :missing (no file), :same (the parameters `normalized`), :other (other parameters) or
# :unreadable (its parameters can't be read, or it is a symbolic link: the store keeps no links). Reads the file again.
function _file_state(path::AbstractString, normalized::AbstractDict)
    ispath(path) || islink(path) || return :missing
    ident = _stored_identity(path; fresh = true)
    return ident === nothing ? :unreadable : ident == _identity(normalized) ? :same : :other
end

# The canonical encoding of the parameters stored in a file (`nothing` if there is none or they can't be read), read
# once per file version: a version is the file's inode, size and modification time, so a file replaced by another
# (also one with the same modification time) is read again. The cache is bounded: it is emptied when it grows beyond
# `_STORED_MAX` files.
const _STORED_IDENTITY = Dict{String, Tuple{Tuple{UInt, Int, Float64}, Union{Nothing, String}}}()
const _STORED_LOCK = ReentrantLock()   # (the pipeline looks files up from several threads)
const _STORED_MAX = 10_000
_file_version(path::AbstractString) = (st = stat(path); (UInt(st.inode), Int(st.size), Float64(st.mtime)))
function _stored_identity(path::AbstractString; fresh::Bool = false)
    (isfile(path) && !islink(path)) || return nothing   # (a link is never taken for a run)
    version = try
        _file_version(path)
    catch
        return nothing
    end
    if !fresh
        hit = lock(() -> get(_STORED_IDENTITY, path, nothing), _STORED_LOCK)
        !isnothing(hit) && hit[1] == version && return hit[2]
    end
    p = _file_params(path)
    clean = _valid_stored(p)
    ident = clean === nothing ? nothing : _identity(clean)
    lock(_STORED_LOCK) do
        length(_STORED_IDENTITY) >= _STORED_MAX && empty!(_STORED_IDENTITY)
        _STORED_IDENTITY[path] = (version, ident)
    end
    return ident
end

"""
    get_file_name(params::AbstractDict)

Returns the path of the data file of the (normalised) parameters, `<save path>/data/<hash>.jld2`
(see [`calculate_hash`](@ref)). Throws a [`SimFileNotFoundError`](@ref) if nothing is stored for them.
"""
function get_file_name(params::AbstractDict)
    isdir(_data_dir()) || throw(SimFileNotFoundError("Data directory $(_data_dir()) does not exist."))
    path = _find_file(params)
    path === nothing && throw(SimFileNotFoundError("No file with matching parameters found in $(_data_dir())."))
    return path
end

# The files in the data folder whose hash starts with `prefix` (or the file of that name, not a link), sorted by name
function _files_matching(prefix::AbstractString)
    clean = lowercase(replace(basename(String(prefix)), r"\.jld2$" => ""))
    isempty(clean) && return String[]
    return filter(_data_files()) do path
        islink(path) && return false   # (the store keeps no links)
        h = _filename_hash(basename(path))
        return lowercase(replace(basename(path), r"\.jld2$" => "")) == clean || (h !== nothing && startswith(h, clean))
    end
end

_has_key(path::AbstractString, key::AbstractString) = jldopen(file -> haskey(file, key), path, "r")

function _load_key(path::AbstractString, key::AbstractString)
    return _open_data(path) do file
        haskey(file, key) || throw(SimFileNotFoundError("Key '$key' not found in $(basename(path))."))
        value = file[key]
        value isa AbstractSimData && (value.metadata = _entry_metadata(_file_metadata(file), key))   # (stored once, next to the data)
        return value
    end
end

# The metadata of the dataset stored under `key`: the file's, marked as a conversion for a cached conversion (as it
# was when it was made: `calculate_all_stats!` must not store it as the native run of its parameters)
_entry_metadata(md::AbstractDict, key::AbstractString) = startswith(key, "conv_") ? _derived_metadata(md, :conversion) : md

# Opens a data file for reading datasets
_open_data(f, path::AbstractString) = jldopen(f, path, "r")

# Every entry of an open file (or group), entries of groups as "group/entry" (like `JLD2.load`); datasets get `md`
function _all_entries!(out::Dict{String, Any}, g, prefix::AbstractString, md::Dict{Symbol, Any})
    for k in keys(g)
        name = isempty(prefix) ? k : string(prefix, "/", k)
        v = g[k]
        if v isa JLD2.Group
            _all_entries!(out, v, name, md)
        else
            v isa AbstractSimData && (v.metadata = _entry_metadata(md, k))   # (`metadata =` copies)
            out[name] = v
        end
    end
    return out
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
    _refuse_link(path)
    tmp = _tmp_path(path)
    try
        cp(path, tmp)
        # (JLD2 reads the types stored in a file it opens to append and may warn about them: harmless, no dataset is read)
        Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            jldopen(tmp, "a+") do file
                for (k, v) in pending
                    haskey(file, k) && delete!(file, k)
                    v isa AbstractSimData ? _write_dataset!(file, k, v) : (file[k] = v)   # (metadata: once, in "metadata")
                end
            end
        end
        mv(tmp, path; force = true)
    catch
        rm(tmp; force = true)
        rethrow()
    end
    return nothing
end

# The store keeps no symbolic links: a writer never writes through one or replaces it
_refuse_link(path::AbstractString) =
    islink(path) && throw(ArgumentError("$path is a symbolic link; the store keeps no links (nothing was written)"))

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

# Copies an entry (recursively for groups, also empty ones) from one open JLD2 file or group to another, with the
# attributes of datasets. Entries are loaded and stored again, so an entry whose type isn't loaded in this session is
# stored as JLD2's reconstruction (warned). A group with attributes (which JLD2 can't write) fails the copy: a rewrite
# never drops what it can't keep.
function _copy_entry!(dest, src, key::AbstractString)
    attrs = JLD2.attributes(JLD2.get_dataset(src, key))
    value = src[key]
    if value isa JLD2.Group
        isempty(attrs) || error("the group '$key' has attributes ($(join(keys(attrs), ", "))), which a rewrite can't keep")
        group = JLD2.Group(dest, key)
        for sub in keys(value)
            _copy_entry!(group, value, sub)
        end
        return nothing
    end
    found = _reconstructed_type(value)
    found === nothing || @warn "Entry '$key' contains a type that isn't loaded in this session ($found); it is " *
        "kept as JLD2's reconstruction. Load the package that defines it before rewriting the data."
    if isempty(attrs)
        dest[key] = value
    else
        dataset = JLD2.create_dataset(dest, key)
        for (k, v) in attrs
            JLD2.add_attribute(dataset, k, v)
        end
        JLD2.write_dataset(dataset, value)
    end
    return nothing
end

# Writes a complete file to a temporary path and renames it into place, so an interrupted write never
# corrupts existing data and rewrites do not grow the file. The dataset's metadata is stored once, as the
# "metadata" entry (the "raw" dataset is stored without it), and a new file always gets a provenance. Entries of
# `previous` that are not managed here (and are not stale conversion caches) are carried over, except `drop`; if one
# can't be copied, nothing is written (an error).
function _write_sim_file(path::AbstractString, data::AbstractSimData, entries::AbstractDict,
                         previous::Union{Nothing, AbstractString}; drop = ())
    _refuse_link(path)
    md = data.metadata
    (previous === nothing || !isfile(previous)) && !haskey(md, :provenance) && (md[:provenance] = _provenance())
    tmp = _tmp_path(path)
    try
        jldopen(tmp, "w") do file
            _write_dataset!(file, "raw", data)
            _write_metadata!(file, data)
            file["metadata"] = md
            for (k, v) in entries
                file[String(k)] = v
            end
            if previous !== nothing && isfile(previous)
                jldopen(previous, "r") do old
                    for k in keys(old)
                        (k in _MANAGED_KEYS || startswith(k, "conv_") || k in drop ||
                         haskey(file, k)) && continue
                        try
                            _copy_entry!(file, old, k)
                        catch e   # (never dropped: the write fails, the file stays as it was)
                            e isa InterruptException && rethrow()
                            throw(ErrorException("Not saved: the entry '$k' of $(basename(previous)) can't be carried over " *
                                                 "($(sprint(showerror, e))); the file is left as it was"))
                        end
                    end
                end
            end
        end
        mv(tmp, path; force = true)
    catch
        rm(tmp; force = true)
        rethrow()
    end
    return path
end

# Stores a dataset without its metadata (a file keeps that once, in "metadata"; `_load_key` puts it back)
_write_dataset!(file, key::AbstractString, data::AbstractSimData) = (file[key] = _without_metadata(data); nothing)

# The same dataset with empty metadata (shares the arrays; the caller's object is left as it is)
_without_metadata(d::ESimData{D, DS, M, T}) where {D, DS, M, T} =
    ESimData{D, DS, M, T}(getfield(d, :params), d.domain, d.axes, getfield(d, :u), _raw_stats(d))
_without_metadata(d::LSimData{D, DS, M, T}) where {D, DS, M, T} =
    LSimData{D, DS, M, T}(getfield(d, :params), d.domain, d.t, d.x, getfield(d, :u), _raw_stats(d))

"""
    save_sim_data(sim_data::AbstractSimData; overwrite = false, verbose = true, metadata = Dict())

Saves the dataset under the hash of its (normalised) parameters, `<save path>/data/<hash>.jld2`, and returns the file
path. The data stored for these parameters is only replaced when `overwrite = true` (which also drops stale
conversion caches); a file at that name that holds other parameters, or whose parameters can't be read, is never
replaced (an error). Neither is a symbolic link at that name: the store keeps no links, it neither writes through
them nor replaces them.
Writes are atomic: data is written to a temporary file that is then renamed into place.
The dataset's `metadata` field is saved with it; `metadata` entries given here are added to it first.
The metadata saved is the dataset's: new data gets a new provenance (`:provenance`) and has no `:sources`,
`:configuration_source` or `:postprocessed` (the stored metadata is replaced); the data stored for its parameters saved again (e.g. after
[`add_stat!`](@ref), or recomputed) takes the pipeline's entries of the stored metadata it doesn't have
(`:postprocessed` only if the data still has the stored statistics). An entry removed from `metadata` stays removed.
`sim_data.params` is replaced by its normalised form (see [`get_clean_params`](@ref)), as stored in the file.
"""
function save_sim_data(sim_data::AbstractSimData; overwrite::Bool = false, verbose::Bool = true,
                       metadata::AbstractDict = Dict{Symbol, Any}())
    isempty(metadata) || merge!(sim_data.metadata, _metadata_dict(metadata))
    path = _find_file(sim_data.params)
    writes = path === nothing || overwrite
    same = (path === nothing || overwrite) && _new_or_same_data!(sim_data, path)
    # the record of what the statistics pass evaluated goes with the statistics it describes: kept for the same data
    # (e.g. a metadata edit) without the statistics the file has and the data no longer has (deleted: due again),
    # dropped with the evaluation records for new data
    # A dataset whose statistics have other values than the stored ones (e.g. an object loaded before a later pass
    # re-evaluated them, or evaluated with another reference without saving) keeps the record of what was evaluated,
    # but not of the reference: unknown (""), so the next pass with a reference evaluates them all again.
    entries = same ? jldopen(path, "r") do f
        haskey(f, "evaluated_stats") || return Dict{String, Any}()
        gone = setdiff(haskey(f, "stat_keys") ? Symbol.(f["stat_keys"]) : Symbol[], keys(_raw_stats(sim_data)))
        e = Dict{String, Any}("evaluated_stats" => filter(n -> !(Symbol(n) in gone), f["evaluated_stats"]))
        stored = _raw_stats(f["raw"])
        all(k -> !haskey(stored, k) || isequal(stored[k], _raw_stats(sim_data)[k]), keys(_raw_stats(sim_data))) ||
            (e["evaluated_reference"] = "")
        return e
    end : Dict{String, Any}()
    drop = same ? () : ("evaluated_with_reference", "evaluated_reference")
    # saved deliberately, it becomes the data of these parameters: a derived dataset is one no more, but only if it is
    # written (a stored native run is kept without `overwrite`: the dataset stays derived)
    derived = writes ? pop!(sim_data.metadata, :derived, nothing) : nothing
    try
        return _save_sim_data(sim_data, overwrite, verbose, entries; drop)
    catch
        isnothing(derived) || (sim_data.metadata[:derived] = derived)
        rethrow()
    end
end

# The metadata of data about to replace the file at `path` (or `nothing`: a new file): the same data keeps the
# stored metadata (missing entries are taken from the file; the post-processing record only if the data still has
# the statistics of the file: a recomputed dataset lacks what a post-processor added); new data gets a provenance
# and loses the entries of the run that made the stored data.
function _new_or_same_data!(data::AbstractSimData, path)
    same = path !== nothing && try
        _is_native_representation(path, data)
    catch e
        e isa InterruptException && rethrow()
        false
    end
    md = data.metadata
    if same
        _carry_metadata!(data, path)
    else
        md[:provenance] = _provenance()
        delete!(md, :sources)
        delete!(md, :configuration_source)
        delete!(md, :postprocessed)
    end
    return same
end

# The same data rewritten (e.g. recomputed, or loaded and saved again): it takes the pipeline's entries of the
# stored metadata it doesn't have (its own entries stay as they are: a removed entry stays removed), the
# post-processing record only if the data still has the stored statistics (a recomputed dataset lacks what a
# post-processor added)
const _PIPELINE_METADATA = (:provenance, :sources, :configuration_source, :postprocessed)
function _carry_metadata!(data::AbstractSimData, path::AbstractString)
    md = data.metadata
    stored = jldopen(f -> _file_metadata(f; strict = true), path, "r")   # (never replace what can't be read)
    for k in _PIPELINE_METADATA
        haskey(md, k) || !haskey(stored, k) || (md[k] = stored[k])
    end
    # (statistics the pipeline evaluated don't count: a statistics pass drops and re-evaluates those)
    missing_stats, evaluated = jldopen(path, "r") do f
        (setdiff(haskey(f, "stat_keys") ? Symbol.(f["stat_keys"]) : Symbol[], keys(data.stats)),
         haskey(f, "evaluated_stats") ? Symbol.(f["evaluated_stats"]) : Symbol[])
    end
    issubset(missing_stats, evaluated) || delete!(md, :postprocessed)
    return data
end

# The metadata of the data in an open file: its "metadata" entry (`strict`: an error if it can't be read, so a writer
# never replaces what it couldn't read; otherwise the data comes without it)
function _file_metadata(file; strict::Bool = false)
    v = try
        file["metadata"]
    catch e   # (e.g. a type whose stored form changed: the data is still readable; writers don't replace it)
        (strict || e isa InterruptException) && rethrow()
        @warn "The metadata of $(basename(file.path)) can't be read; the data is loaded without it" exception = e
        return Dict{Symbol, Any}()
    end
    return v isa AbstractDict ? _metadata_dict(v) : Dict{Symbol, Any}(:metadata => v)
end

# Changes the stored metadata of a file without rewriting its data (`nothing` removes an entry)
function _update_metadata!(path::AbstractString, changes::Pair...)
    md = jldopen(f -> _file_metadata(f; strict = true), path, "r")
    for (k, v) in changes
        v === nothing ? delete!(md, k) : (md[k] = v)
    end
    if Base.summarysize(md) > 2^20   # (appending would leave a copy of large metadata in the file every time)
        _rewrite_file!(path, changes...) === :rewritten || error("$(basename(path)) can't be rewritten: its data doesn't load")
    else
        _set_key!(path, "metadata", md)
    end
    return md
end


# --- Provenance ------------------------------------------------------------------------------------------------

"""
    _provenance(; solver = nothing, wall_time = nothing, commit = _git_commit())

How data was made (`data.metadata[:provenance]`): the versions of PDEStudioCore and Julia, the host, the
time, the number of threads and the git commit of the active project, and for data a solver made, the solver (name,
module, package version) and its wall time in seconds.
"""
function _provenance(; solver = nothing, wall_time = nothing, commit = _git_commit())
    p = Dict{Symbol, Any}(:pdestudiocore => string(pkgversion(@__MODULE__)), :julia => string(VERSION),
                          :host => gethostname(), :created => string(now()), :threads => Threads.nthreads())
    isnothing(commit) || (p[:git_commit] = commit)
    if !isnothing(solver)
        p[:solver] = _func_name(solver)
        root = _func_package(solver)
        isnothing(root) || (p[:solver_module] = string(nameof(root)))
        v = _func_version(solver)
        isnothing(v) || (p[:solver_version] = v)
    end
    isnothing(wall_time) || (p[:wall_time] = Float64(wall_time))
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
function _save_sim_data(sim_data::AbstractSimData, overwrite::Bool, verbose::Bool, metadata::AbstractDict; drop = ())
    normalized = _normalize_params(sim_data.params)
    empty!(sim_data.params)
    merge!(sim_data.params, normalized)

    path = _hash_path(calculate_hash(normalized))
    # (read again, a cached identity may be stale: only a file holding these parameters is ever replaced)
    state = _file_state(path, normalized)
    if state === :missing
        mkpath(_data_dir())
        _write_sim_file(path, sim_data, metadata, nothing)
        verbose && @info "Saved simulation data to $(basename(path))"
    elseif state === :same
        if overwrite
            _write_sim_file(path, sim_data, metadata, path; drop)
            verbose && @info "Saved simulation data to $(basename(path)) (replaced; conversion caches cleared)"
        else
            verbose && @info "Not saved: data of these parameters is stored already ($(basename(path))); " *
                             "`overwrite = true` replaces it."
        end
    else   # (never replaced: it isn't the data of these parameters, or it can't be checked)
        throw(_name_taken(path, state))
    end
    return path
end

# The error for a file name of parameters that is taken by a file of other parameters (`state = :other`) or one whose
# parameters can't be read (`:unreadable`): such a file is never replaced
_name_taken(path::AbstractString, state::Symbol) = ErrorException(
    "Not saved: $path, the file of these parameters, " *
    (state === :other ? "holds the data of other parameters" :
     islink(path) ? "is a symbolic link (the store keeps no links)" : "is there, but its parameters can't be read") *
    " (it was put there from outside). Inspect it (`load_sim_data(\"" * first(basename(path), 12) * "\")`), move or " *
    "delete it, then save again.")

# Throws `_name_taken` if the file name of these parameters is taken (checked before a run, whose result couldn't be saved)
function _check_name_free(params::AbstractDict)
    clean = _normalize_params(params)
    path = _hash_path(calculate_hash(clean))
    state = _file_state(path, clean)
    state in (:other, :unreadable) && throw(_name_taken(path, state))
    return nothing
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
    return jldopen(file -> (file["native"], Tuple(file["shape"])), path, "r")
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
and `n_steps` the number of stored time steps (0 for static data). Throws a [`SimFileNotFoundError`](@ref) if nothing
is stored for `params`.
"""
function get_sim_data_info(params::AbstractDict)
    path = get_file_name(params)
    # (one opening, so a concurrent overwrite can't pair the shape of one file with the axes of another)
    kind, shape, dim_keys, time_dim = jldopen(path, "r") do file
        file["native"], Tuple(file["shape"]), Tuple(file["dim_keys"]), file["time_dim"]
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

Loads a file by (a prefix of) its parameter hash or by its file name (the matching files sorted by name). Returns the
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
    key === nothing || return _load_key(path, String(key))
    return _open_data(path) do file   # (every entry, groups as "group/entry"; the datasets with the file's metadata)
        _all_entries!(Dict{String, Any}(), file, "", _file_metadata(file))
    end
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

# A file the pipeline can use: its dataset and fast metadata (a file without them counts as missing: the pipeline
# computes the run again and replaces it)
_is_current_file(path::AbstractString) = jldopen(f -> all(k -> haskey(f, k), ("raw", "native", "shape", "params")), path, "r")

# The format version of an open data file (see `_FORMAT_VERSION`; a user entry of that name in a file of 0.4, where
# it wasn't reserved, doesn't count)
function _format_version(file)
    v = haskey(file, "format_version") ? file["format_version"] : nothing
    v isa Integer && v >= 2 && haskey(file, "dim_keys") || return haskey(file, "native") && haskey(file, "shape") ? 1 : 0
    return v >= 3 && !haskey(file, "metadata") ? 2 : Int(v)   # (written by these versions)
end

# Writes a file again, with the same data (and metadata `changes`): :rewritten, or :unreadable
function _rewrite_file!(path::AbstractString, changes::Pair...)
    raw = try
        _load_key(path, "raw")   # (read with the metadata the file holds)
    catch e
        e isa InterruptException && rethrow()
        nothing
    end
    raw isa AbstractSimData || return :unreadable
    for (k, v) in changes   # (metadata changes, written in the same rewrite)
        v === nothing ? delete!(raw.metadata, k) : (raw.metadata[k] = v)
    end
    # the same data again: what was evaluated for it stays valid (conversion caches are dropped)
    entries = jldopen(f -> haskey(f, "evaluated_stats") ? Dict{String, Any}("evaluated_stats" => f["evaluated_stats"]) :
                           Dict{String, Any}(), path, "r")
    _write_sim_file(path, raw, entries, path)
    return :rewritten
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
