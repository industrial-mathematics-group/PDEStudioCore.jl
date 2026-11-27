# ==============================================================================
# CONFIGURATION FILES: parameter literals, the configuration a file ends with, source bundles
# ==============================================================================

# ------------------------------------------------------------------------------
# Parameter values as literals
# ------------------------------------------------------------------------------

# Values `val2str` writes without their type: `Float32`/`Float16` numbers (as `1.5`, read back as `Float64`) and static
# vectors (as `Float64[…]`, read back as `Vector`), also inside tuples, untyped vectors and dictionaries; and values
# it writes as something else: pairs (as `Pair(first=…, second=…)`), and `nothing` and `missing` inside a container
# (as the types `Nothing`, `Missing`).
_needs_literal(v) = v isa Union{Float32, Float16} || v isa SVector ||
                    v isa Pair || (v isa Tuple && any(_needs_literal_inside, v)) ||
                    (v isa AbstractVector && ((!isconcretetype(eltype(v)) && any(_needs_literal, v)) || any(_literal_inside, v))) ||
                    (v isa AbstractDict && any(p -> _needs_literal_inside(p.first) || _needs_literal_inside(p.second), v))
_literal_inside(x) = x === nothing || x === missing || x isa Pair
_needs_literal_inside(x) = _literal_inside(x) || _needs_literal(x)

# The literal of a value inside another one (`1.5f0`, `SA{Float64}[1.0, 2.0]`, `(nothing, 1.0)`, `:a => 1`,
# `Dict{Symbol, Any}(:a => nothing)`); everything else as `val2str` writes it there.
function _literal_text(v)
    v === nothing && return "nothing"
    v === missing && return "missing"
    _needs_literal(v) || return val2str(v; top_level = false)
    v isa Union{Float32, Float16} && return repr(v)
    if v isa Pair
        side(x) = x isa Pair ? "($(_literal_text(x)))" : _literal_text(x)
        return "$(side(v.first)) => $(side(v.second))"
    end
    if v isa AbstractDict
        entries = sort!(["$(_literal_text(k)) => $(_literal_text(x))" for (k, x) in v])
        return "Dict{$(keytype(v)), $(valtype(v))}($(join(entries, ", ")))"
    end
    elements = join(map(_literal_text, collect(v)), ", ")
    v isa SVector && return "SA{$(eltype(v))}[$elements]"
    v isa Tuple && return length(v) == 1 ? "($elements,)" : "($elements)"
    return (eltype(v) === Any ? "Any" : string(eltype(v))) * "[$elements]"
end

"""
    param_literal(v) -> String

The text of the parameter value `v` for a file of values (a CSV cell, a line of a configuration): a literal that
[`str2val`](@ref) reads back as `v`, with its type. Where [`val2str`](@ref) (the text of the *identity*, which the
hash is made of) loses the type or writes another value, the literal keeps it:

- `Float32` / `Float16` numbers and static vectors are written with their type (`1.5f0`, `SA{Float64}[1.0, 2.0]`),
  also inside tuples, untyped vectors and dictionaries;
- pairs are written as `:a => 1`, and `nothing` and `missing` as they are, also inside a container;
- text is written as it is where it reads back as itself, and quoted otherwise (`"1e3"`, `"Float64"`, `" padded "`).

Everything else is written as `val2str` writes it. A value whose literal doesn't read back as the value is an
*object* (a struct, an enum, …; see [`is_param_object`](@ref)): its text is its identity, and only the code that
built it can build it again.

```julia
param_literal(1.5f0)              # "1.5f0"
param_literal((nothing, 1.0))     # "(nothing, 1.0)"
param_literal("1e3")              # "\\"1e3\\""
str2val(param_literal(:a => 1))   # :a => 1
```
"""
function param_literal(v)
    if v isa AbstractString
        plain = !isempty(v) && v == strip(v) && isequal(str2val(v), v)
        return plain || isempty(v) ? String(v) : repr(String(v))
    end
    (v === nothing || v === missing) && return _literal_text(v)   # (`val2str` writes the types `Nothing`, `Missing`)
    return _needs_literal(v) ? _literal_text(v) : val2str(v)
end

"""
    is_param_object(v) -> Bool

Whether the parameter value `v` is an *object*: a value a file of values can only hold as text, because its literal
([`param_literal`](@ref)) doesn't read back as the value. These are structs (with an identity, see
[`@param_struct`](@ref)), enums and containers holding one, and values beyond the size limits of [`str2val`](@ref)
(more than 10^6 elements, more than 32 levels of nesting). Numbers, text, Symbols, `nothing`, tuples, pairs, arrays
and dictionaries of them are data.

Objects come from code: a file of values (PDEStudio's CSV export) marks them, and takes them from the configuration
that the configuration's source files build (see "Source files" in the manual).
"""
function is_param_object(v)
    return try
        !isequal(str2val(param_literal(v)), v)
    catch
        true
    end
end

# ------------------------------------------------------------------------------
# The configuration a file ends with
# ------------------------------------------------------------------------------

"""
    to_simulation_config(result, name) -> SimulationConfig

The configuration that `result` stands for, the last value of a configuration file (or a value named `name`, used
in the errors): a [`SimulationConfig`](@ref), or a function without arguments that returns one, which is called.
Everything else is an `ArgumentError`: another value, a function that returns no configuration, and a function with
arguments, also optional or keyword ones (`get_config(N = 12)` is not called with its defaults).

Methods a function got before, e.g. from an earlier version of the file, stay until Julia restarts: a file that was
refused for `get_config(N = 12)` is refused again after the argument is removed. Rename the function then, or end
the file with `() -> SimulationConfig(…)`.
"""
function to_simulation_config(result, name::AbstractString)
    if result isa Function
        ms = methods(result)
        isempty(ms) && throw(ArgumentError("$name: the function $(nameof(result)) has no methods; a configuration is a " *
                                           "SimulationConfig, or a function without arguments that returns one"))
        if any(m -> m.nargs != 1 || m.isva || !isempty(Base.kwarg_decl(m)), ms)
            throw(ArgumentError("$name: the function $(nameof(result)) takes arguments; a configuration is a " *
                                "SimulationConfig, or a function without arguments that returns one. (Methods defined " *
                                "before, e.g. by an earlier version of the file, stay until Julia restarts: rename " *
                                "the function, or end the file with `() -> …`.)"))
        end
        f, result = result, Base.invokelatest(result)
        result isa SimulationConfig ||
            throw(ArgumentError("$name: the function $(nameof(f)) returned " *
                                "$(result === nothing ? "nothing" : "a $(typeof(result))"), not a SimulationConfig"))
    end
    result isa SimulationConfig ||
        throw(ArgumentError("$name must end with a SimulationConfig (or a function without arguments that returns " *
                            "one); it returned $(result === nothing ? "nothing" : "a $(typeof(result))")"))
    return result
end

_same_file(a::AbstractString, b::AbstractString) =
    normpath(abspath(a)) == normpath(abspath(b)) || (isfile(a) && isfile(b) && samefile(a, b))

# `sources` with `file` as the last entry (moved there if listed, appended otherwise), as absolute paths
_with_last_source(sources::AbstractVector, file::AbstractString) =
    String[String[abspath(src) for src in sources if !_same_file(src, file)]; abspath(file)]

"""
    load_config_file(path; mod = get_target_module(), within = nothing, included = nothing) -> SimulationConfig

Runs the configuration file `path` in the module `mod` and returns the configuration it ends with: its last value is a
[`SimulationConfig`](@ref), or a function without arguments that returns one (see [`to_simulation_config`](@ref)).
The file becomes the last of the configuration's `sources` (moved there if the configuration lists it elsewhere,
added otherwise), so a run includes it after the helper files and records its digest.

Pass a vector as `included` to get every file that ran: the file itself and the files it includes (its helpers, also
the ones they include; absolute paths, not the files of packages). These are what a copy of the configuration's code
needs besides its `sources` (see [`bundle_sources`](@ref)).

With `within = dir`, an `include` of a file outside the folder `dir` is refused with an `ArgumentError` before the
file runs (see [`include_sources`](@ref)).

!!! warning
    This **executes the file's code**: only load files you trust.
"""
function load_config_file(path::AbstractString; mod::Module = get_target_module(),
                          within::Union{Nothing, AbstractString} = nothing,
                          included::Union{Nothing, AbstractVector{<:AbstractString}} = nothing)
    file = abspath(path)
    isfile(file) || throw(ArgumentError("configuration file not found: $file"))
    result, files = _record_includes(within) do
        Base.include(mod, file)
    end
    config = to_simulation_config(result, basename(file))
    config.sources = _with_last_source(config.sources, file)
    included === nothing || append!(empty!(included), files)
    return config
end

# ------------------------------------------------------------------------------
# Included files
# ------------------------------------------------------------------------------

# Whether `path` lies inside the folder `dir` (both resolved: links count as what they point to)
function _is_inside(path::AbstractString, dir::AbstractString)
    resolved(p) = ispath(p) ? realpath(p) : normpath(abspath(p))
    return startswith(resolved(path), rstrip(resolved(dir), Base.Filesystem.path_separator[1]) * Base.Filesystem.path_separator)
end

# Whether `path` is a file of the package the module `m` belongs to (its `include`s while it loads)
function _package_file(m::Module, path::AbstractString)
    dir = pkgdir(Base.moduleroot(m))
    return dir !== nothing && _is_inside(path, dir)
end

# Runs `f()` and returns `(result, files)`: every file that was included meanwhile in this task (absolute paths, in the
# order of their first include; not the files of packages). With `within`, an include of a file outside that folder
# throws before the file runs. (Uses Julia's include callbacks, which Revise relies on; without them nothing is
# recorded or refused.)
function _record_includes(f, within::Union{Nothing, AbstractString} = nothing)
    files = String[]
    isdefined(Base, :include_callbacks) || return f(), files
    task = current_task()
    callback = function (m::Module, path::AbstractString)
        (current_task() === task && !_package_file(m, path)) || return nothing
        file = abspath(path)
        if within !== nothing && !_is_inside(file, within)
            throw(ArgumentError("$file was included from outside $(abspath(within)): the source files there run on " *
                                "their own (list the file in the configuration's `sources`, or include it relative " *
                                "to the file that needs it, so it is bundled with them)"))
        end
        file in files || push!(files, file)
        return nothing
    end
    push!(Base.include_callbacks, callback)
    try
        return f(), files
    finally
        i = findfirst(c -> c === callback, Base.include_callbacks)
        i === nothing || deleteat!(Base.include_callbacks, i)
    end
end

"""
    include_sources(sources; mod = get_target_module(), within = nothing) -> Vector{String}

Includes the source files of a configuration into the module `mod`, in their order (the helpers, then the
configuration's own file), as [`run_all_simulations`](@ref) does before a run, and returns every file that was
included: the sources and the files they include themselves (absolute paths; not the files of packages).

With `within = dir`, the sources must run on their own inside the folder `dir` (a bundle, see
[`bundle_sources`](@ref)): an `include` of a file outside it is refused with an `ArgumentError` before that file runs.
This holds for `include`; code that reads or evaluates files in other ways (`evalfile`, `read`) is not seen.
"""
function include_sources(sources::AbstractVector{<:AbstractString}; mod::Module = get_target_module(),
                         within::Union{Nothing, AbstractString} = nothing)
    _check_sources(sources)
    _, files = _record_includes(within) do
        for file in sources
            path = abspath(file)
            isfile(path) || throw(ArgumentError("source file not found: $path"))
            Base.include(mod, path)
        end
    end
    return files
end

# ------------------------------------------------------------------------------
# Source bundles
# ------------------------------------------------------------------------------

# The folder all `files` (absolute paths) lie in: the longest common leading part of their folders
function _common_folder(files::AbstractVector{<:AbstractString})
    drives = unique!(map(f -> first(splitdrive(f)), files))
    length(drives) == 1 || throw(ArgumentError("the source files lie on different drives ($(join(drives, ", "))): " *
                                               "they can't be bundled in one folder"))
    parts = map(f -> splitpath(dirname(f)), files)
    n = 0
    while all(p -> length(p) > n, parts) && all(p -> p[n + 1] == parts[1][n + 1], parts)
        n += 1
    end
    return joinpath(parts[1][1:n]...)
end

"""
    bundle_sources(sources, dir; extra = String[]) -> (sources = [...], extra = [...])

Copies the source files of a configuration into the folder `dir` (created if needed), so that they run there on their
own: each file keeps its path relative to the folder all of them lie in, so a file that includes another one by a
relative path (`include("lib/solver.jl")`) finds its copy. `extra` are files the sources include themselves without
listing them (as [`load_config_file`](@ref) and [`include_sources`](@ref) report them): they are copied along, but
are no sources of the bundle.

Returns the paths of the copies relative to `dir` (with `/` between folders, on every system): `sources` in the order
given, the configuration's own file last (`joinpath.(dir, …)` are the sources of the bundle), and the `extra` files
that aren't sources.

Files that are in place already are left as they are, other files in `dir` too. A file that doesn't exist, or files
on different drives, are an `ArgumentError`. Data files the code reads are not part of a bundle.
"""
function bundle_sources(sources::AbstractVector{<:AbstractString}, dir::AbstractString;
                        extra::AbstractVector{<:AbstractString} = String[])
    isempty(sources) && return (sources = String[], extra = String[])
    files = String[abspath(src) for src in sources]
    _check_sources(files)
    extras = String[]
    for file in extra   # (a file once, also under another path)
        any(f -> _same_file(f, file), files) || any(f -> _same_file(f, file), extras) || push!(extras, abspath(file))
    end
    for file in Iterators.flatten((files, extras))
        isfile(file) || throw(ArgumentError("source file not found: $file"))
    end
    root = _common_folder(String[files; extras])
    relative(file) = relpath(file, root)
    for file in Iterators.flatten((files, extras))
        target = joinpath(abspath(dir), relative(file))
        mkpath(dirname(target))
        # (a symlinked source is copied as a file: the bundle must not follow later edits)
        (ispath(target) && samefile(file, target)) || cp(file, target; force = true, follow_symlinks = true)
    end
    portable(file) = join(splitpath(relative(file)), "/")
    return (sources = map(portable, files), extra = map(portable, extras))
end
