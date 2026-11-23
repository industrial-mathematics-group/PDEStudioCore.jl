# ==============================================================================
# --- Tabulated data: numbers from outside a simulation as a method ---
# ==============================================================================

"""
    tabulated_method(table::AbstractDict; key = nothing, ignore = Symbol[]) -> ParamDict

The parameters of a method whose data is a table: numbers from outside a simulation (the errors a paper reports, a
measurement, a reference curve) as a method of a [`SimulationConfig`](@ref), so they are run, cached, plotted,
compared and exported like every other method, and written to configuration files with the configuration.

`table` maps column names to vectors of the same length; `key` names the column the data is looked up by:

- **a parameter** (`key = :N`): the method yields one dataset per value of `N` the sweep asks for, carrying the
  other columns as scalar statistics of that row (`:l1error => 2e-3`, with the kept dimensions the statistic is
  registered with, so it is shown like a computed one). A value of `N` the table has no row for gives
  `NoSimData()`: a gap. The key is also set as a parameter of the method, so a sweep over it applies.
- **a coordinate** (`key = :x`, the default when the table has an `x` column; also `:y`, `:z`): one static 1D
  dataset, a profile `u(x)`, from the column `u` (or the only other column).

`ignore` lists the shared parameters the method does not use, usually all of them (`collect(keys(shared))`): the
table's rows don't depend on them (the key column is kept as a parameter in any case). The solver is the built-in [`tabulated_data`](@ref), found by name in every
target module.

```julia
paper = tabulated_method(Dict(:N => [40, 80, 160], :l1error => [2.1e-3, 5.4e-4, 1.4e-4]); key = :N,
                         ignore = collect(keys(shared)))
config = SimulationConfig(shared, Dict(:upwind => upwind, :paper => paper); varied = Dict(:N => [40, 80, 160]))
```
"""
function tabulated_method(table::AbstractDict; key::Union{Nothing, Symbol} = nothing, ignore = Symbol[])
    tab = Dict{Symbol, Any}(Symbol(k) => collect(v) for (k, v) in table)
    isempty(tab) && throw(ArgumentError("tabulated_method: the table has no columns"))
    n = length(first(values(tab)))
    n >= 1 || throw(ArgumentError("tabulated_method: the table has no rows"))
    all(v -> v isa AbstractVector && length(v) == n, values(tab)) ||
        throw(ArgumentError("tabulated_method: every column must be a vector of the same length ($n)"))
    if isnothing(key)
        haskey(tab, :x) || throw(ArgumentError("tabulated_method: give `key`, the column the data is looked up by " *
                                                "(a swept parameter such as :N, or the coordinate :x)"))
        key = :x
    end
    haskey(tab, key) || throw(ArgumentError("tabulated_method: the table has no column $key"))
    key in (:x, :y, :z) || all(v -> v isa Real || v isa AbstractString || v isa Symbol, tab[key]) ||
        throw(ArgumentError("tabulated_method: the key column $key must hold numbers or names"))
    # (the key column stays a parameter of the method, so a sweep over it applies: an ignored key is not swept)
    params = create_param_dict(:sim_func_name => :tabulated_data, :table => tab, :table_key => key,
                               :ignore => Symbol[Symbol(k) for k in ignore if Symbol(k) !== key])
    key in (:x, :y, :z) || (params[key] = first(tab[key]))   # (a parameter: a sweep over it sets it per task)
    return params
end

"""
    tabulated_data(params) -> AbstractSimData

The built-in solver of [`tabulated_method`](@ref): returns the dataset of the table row `params[:table_key]`
selects (`NoSimData()` if there is none), or the profile over a coordinate. Resolved by name in every target
module.
"""
function tabulated_data(params::AbstractDict)
    tab = params[:table]
    key = Symbol(params[:table_key])
    haskey(tab, key) || throw(ArgumentError("tabulated_data: the table has no column $key"))
    col = collect(tab[key])
    if key in (:x, :y, :z)
        others = [k for k in keys(tab) if Symbol(k) !== key]
        ucol = haskey(tab, :u) ? tab[:u] : length(others) == 1 ? tab[only(others)] :
               throw(ArgumentError("tabulated_data: a profile needs a column `u` (or exactly one other column)"))
        x = Float64.(col)
        p = sortperm(x)
        return create_sim_data(x[p], Float64.(collect(ucol))[p], params; dims = key)
    end
    haskey(params, key) || throw(ArgumentError("tabulated_data: the parameters have no $key to look the row up by"))
    i = findfirst(v -> _tabulated_equal(v, params[key]), col)
    isnothing(i) && return NoSimData()
    # a carrier for the row's statistics: two points, one time (a single point has no spacing)
    data = create_sim_data([0.0, 1.0], fill(NaN, 2, 1), [0.0], params)
    reg = data.domain.stat_registry
    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do   # (add_stat! reports every statistic)
        for (name, vals) in tab
            name = Symbol(name)
            name === key && continue
            v = vals[i]
            v isa Real || continue
            if haskey(reg, name)   # the shape of the registered statistic over this carrier
                shape = Tuple(length(data.axes[k]) for k in get_kept_indices(name, data.domain))
                add_stat!(data, name, isempty(shape) ? v : fill(Float64(v), shape), reg[name])
            else
                add_stat!(data, name, v, Symbol[])
            end
        end
    end
    return data
end

# A row's key equals the run's parameter: numbers up to rounding (the sweep's value may be `40` or `40.0`), names as text
_tabulated_equal(a, b) = isequal(a, b) || (a isa Real && b isa Real && isapprox(a, b; rtol = 1e-9, atol = 0)) ||
                         (!(a isa Real) && !(b isa Real) && string(a) == string(b))

# Solvers every target module finds by name (see `resolve_dynamic_function`)
const _BUILTIN_SOLVERS = Dict{Symbol, Function}(:tabulated_data => tabulated_data)
