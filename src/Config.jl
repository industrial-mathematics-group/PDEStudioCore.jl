# ==============================================================================
# --- Pipeline configuration ---
# ==============================================================================

"""
    SimulationConfig

Blueprint of a batch of simulation runs.

# Fields
- `shared::ParamDict`: baseline parameters of every run (usually contains `:sim_func_name`).
- `methods::MethodDict`: per-method parameter overrides (`:ignore => [...]` drops shared keys).
- `defaults::Vector{Symbol}`: the methods [`run_all_simulations`](@ref) executes.
- `varied::VariedDict`: the parameter sweep (Cartesian product).
- `reference::Union{Symbol, Nothing}`: name of a reference *factory* `params -> (x -> u_exact)`.
- `postprocess::Union{Symbol, Nothing}`: name of a function `data -> Bool` run on every dataset after the
  statistics (return `true` to save the modified data; the data itself is saved either way).
- `sources::Vector{String}`: files included into the target module before running.
"""
mutable struct SimulationConfig
    shared::ParamDict
    methods::MethodDict
    defaults::Vector{Symbol}
    varied::VariedDict
    reference::Union{Symbol, Nothing}
    postprocess::Union{Symbol, Nothing}
    sources::Vector{String}
end

_optional_name(::Nothing) = nothing
_optional_name(name::Union{Symbol, AbstractString}) = Symbol(name)
_optional_name(f::Function) = nameof(f)

# Normalises a loosely typed value for a SimulationConfig field (used by the constructor and setproperty!).
function _config_field(field::Symbol, value)
    if field === :shared
        return _to_paramdict(value)
    elseif field === :methods
        return MethodDict(Symbol(k) => _to_paramdict(v) for (k, v) in value)
    elseif field === :defaults
        return value isa Union{Symbol, AbstractString} ? [Symbol(value)] : Symbol[Symbol(m) for m in value]
    elseif field === :varied
        return _to_varieddict(value)
    elseif field === :reference || field === :postprocess
        return _optional_name(value)
    elseif field === :sources
        return value isa AbstractString ? [String(value)] : String[String(s) for s in value]
    end
    throw(ArgumentError("SimulationConfig has no field `$field`"))
end

"""
    SimulationConfig(shared, methods = Dict(), defaults = all methods;
                     varied = Dict(), reference = nothing, postprocess = nothing, sources = String[])

Builds a [`SimulationConfig`](@ref), converting loosely typed dictionaries (string or symbol keys)
into [`ParamDict`](@ref)/[`MethodDict`](@ref)/[`VariedDict`](@ref). Without `methods`, every run uses
the shared parameters only. Functions are referenced by name (resolved in [`get_target_module`](@ref)).
"""
function SimulationConfig(shared::AbstractDict = ParamDict(), methods::AbstractDict = MethodDict(),
                          defaults = sort!(Symbol[Symbol(k) for k in keys(methods)]);
                          varied::AbstractDict = VariedDict(),
                          reference = nothing,
                          postprocess = nothing,
                          sources::Union{AbstractString, AbstractVector} = String[])
    methods_p = _config_field(:methods, methods)
    defaults_v = _config_field(:defaults, defaults)
    for m in defaults_v
        if !haskey(methods_p, m) && !isempty(methods_p) && !is_reference_method(m)
            @warn "SimulationConfig: method :$m is not defined in `methods`; it will run with the shared parameters only."
        end
    end

    return SimulationConfig(_config_field(:shared, shared), methods_p, defaults_v, _config_field(:varied, varied),
                            _config_field(:reference, reference), _config_field(:postprocess, postprocess),
                            _config_field(:sources, sources))
end

# Assigning a field accepts the same loose input as the constructor (e.g. `config.defaults = :upwind`).
Base.setproperty!(config::SimulationConfig, name::Symbol, value) = setfield!(config, name, _config_field(name, value))

"""
    resolve_dynamic_function(name, provided = nothing)

Looks up the function called `name` (a `Symbol` or `String`) in the target module
(see [`set_target_module!`](@ref)), then among the solvers and references of the built-in examples
([`PDEStudioCore.Examples`](@ref)). A function passed as `provided` (or as `name`) is returned directly.
Returns `nothing` (with a warning) if the name cannot be resolved.

Only names the target module (or one of its submodules) defines itself are accepted: names it merely imports
(exports of `Base`, of PDEStudioCore or of other packages) are not, so a configuration file cannot run e.g.
`delete_sim_data` or `rm` as its reference or solver. Define a wrapper in the target module to use such a function.
"""
function resolve_dynamic_function(name, provided::Union{Function, Nothing} = nothing)
    provided === nothing || return provided
    name === nothing && return nothing
    name isa Function && return name
    sym = Symbol(name)
    sym === :none && return nothing
    mod = get_target_module()
    # Look the binding up in the latest world, so functions defined after the caller started
    # (e.g. by including source files) are found.
    f = Base.invokelatest(_lookup_global, mod, sym)
    f === nothing && (f = _lookup_global(Examples, sym))
    f === nothing && @warn "Could not resolve function `$sym` in module $mod: it must be defined in that module " *
                           "(or a submodule), imported names are not accepted (did you call `set_target_module!`?)."
    return f
end

# The binding `sym` of `mod` if `mod` (or one of its submodules) created it. `isdefined` alone would also find every
# imported binding, such as the exports of Base and of PDEStudioCore: a values-only configuration file (loaded
# without a confirmation) could then name `delete_sim_data` as its reference and run it.
function _lookup_global(mod::Module, sym::Symbol)
    isdefined(mod, sym) || return nothing
    owner = try
        which(mod, sym)   # the module that created the binding
    catch
        return nothing
    end
    _is_submodule(owner, mod) || return nothing
    return getglobal(mod, sym)
end

# `m` is `root` or (transitively) one of its submodules. Another top-level module (Base, Core, a loaded package) is
# not part of `root`, although its parent is `Main` like that of a module defined in `Main`.
function _is_submodule(m::Module, root::Module)
    while true
        m === root && return true
        Base.is_root_module(m) && return false
        parent = parentmodule(m)
        parent === m && return false
        m = parent
    end
end
