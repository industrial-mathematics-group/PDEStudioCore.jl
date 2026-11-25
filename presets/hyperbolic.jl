# 1. Register the metrics into the active registry
register_stat!(:mass, :time)
register_stat!(:l1norm, :time)
register_stat!(:l2norm, :time)
register_stat!(:wave_height, :time)
register_stat!(:l1error, :time)
register_stat!(:l2error, :time)
register_stat!(:relative_l2error, :time)
register_stat!(:relative_l1error, :time)
register_stat!(:relative_mass, :time)
register_stat!(:spacetime_relative_mass, Symbol[])
register_stat!(:mass_error, :time)
register_stat!(:mass_signed_error, :time)

# ==============================================================================
# --- STANDARD METRICS (of the data alone: no reference argument, the simulation layer) ---
# ==============================================================================
# (The sums are taken in at least Float64 and converted to the data's precision at the end, see `_wide_sum`: the
# squares of Float16 values overflow from 256 on.)

function calc_stat(::Val{:mass}, fixed_coords, u, domain::DomainInfo)
    return _narrow(u, _wide_sum(identity, u, _wide_measure(:mass, domain)))
end

function calc_stat(::Val{:l1norm}, fixed_coords, u, domain::DomainInfo)
    return _narrow(u, _wide_sum(v -> abs.(v), u, _wide_measure(:l1norm, domain)))
end

function calc_stat(::Val{:l2norm}, fixed_coords, u, domain::DomainInfo)
    return _narrow(u, sqrt.(_wide_sum(v -> abs2.(v), u, _wide_measure(:l2norm, domain))))
end

function calc_stat(::Val{:wave_height}, fixed_coords, u, domain::DomainInfo)
    # A Lagrangian step can have no particles at all; there is no maximum then.
    isempty(u) && return map(_ -> oftype(zero(eltype(eltype(u))), NaN), zero(eltype(u)))
    return reduce((a, b) -> max.(a, b), u)
end


# ==============================================================================
# --- ERROR METRICS (they use the reference: the reference layer, evaluated with a reference only) ---
# ==============================================================================
function calc_stat(::Val{:l1error}, fixed_coords, u, ana, domain::DomainInfo)
    return _narrow(u, _wide_sum((v, a) -> abs.(v - a), u, ana, _wide_measure(:l1error, domain)))
end

function calc_stat(::Val{:relative_l1error}, fixed_coords, u, ana, domain::DomainInfo)
    measure = _wide_measure(:relative_l1error, domain)
    error_norm = _wide_sum((v, a) -> abs.(v - a), u, ana, measure)
    ana_norm = _wide_sum(a -> abs.(a), ana, measure)
    return _narrow(u, error_norm ./ ana_norm)
end

function calc_stat(::Val{:l2error}, fixed_coords, u, ana, domain::DomainInfo)
    return _narrow(u, sqrt.(_wide_sum((v, a) -> abs2.(v - a), u, ana, _wide_measure(:l2error, domain))))
end

function calc_stat(::Val{:relative_l2error}, fixed_coords, u, ana, domain::DomainInfo)
    measure = _wide_measure(:relative_l2error, domain)
    error_norm = sqrt.(_wide_sum((v, a) -> abs2.(v - a), u, ana, measure))
    ana_norm = sqrt.(_wide_sum(a -> abs2.(a), ana, measure))
    return _narrow(u, error_norm ./ ana_norm)
end

# The ratio of the masses per component, `NaN` where the reference's mass is negligible against its L1 norm (a field
# whose mass cancels, e.g. a sine wave: the ratio would be round-off over round-off). Relative, so small fields (SI units)
# keep it.
function _relative_mass(u, ana, measure)
    sum_u, sum_ana = _wide_sum(identity, u, measure), _wide_sum(identity, ana, measure)
    l1_ana = _wide_sum(a -> abs.(a), ana, measure)
    T = eltype(eltype(u))
    return SVector{length(eltype(u)), T}(ntuple(length(eltype(u))) do c
        abs(sum_ana[c]) <= 1e-9 * l1_ana[c] ? T(NaN) : T(sum_u[c] / sum_ana[c])
    end)
end

function calc_stat(::Val{:relative_mass}, fixed_coords, u, ana, domain::DomainInfo)
    return _relative_mass(u, ana, _wide_measure(:relative_mass, domain))
end

function calc_stat(::Val{:mass_error}, fixed_coords, u, ana, domain::DomainInfo)
    measure = _wide_measure(:mass_error, domain)
    sum_u = _wide_sum(identity, u, measure)
    sum_ana = _wide_sum(identity, ana, measure)
    # (the measured error, also below 1e-9: exact conservation shows as round-off or 0, not as a floor value)
    m_err = abs.(sum_u - sum_ana)
    M = length(eltype(u))
    T = eltype(eltype(u)) # Dynamically get T
    return SVector{M, T}(ntuple(c -> T(m_err[c]), M))
end
function calc_stat(::Val{:mass_signed_error}, fixed_coords, u, ana, domain::DomainInfo)
    measure = _wide_measure(:mass_signed_error, domain)
    return _narrow(u, _wide_sum(identity, u, measure) - _wide_sum(identity, ana, measure))
end

# 2. Add the calc_stat overload
function calc_stat(::Val{:spacetime_relative_mass}, fixed_coords, u, ana, domain::DomainInfo)
    # the combined integration measure dx * dy * dz * dt
    return _relative_mass(u, ana, _wide_measure(:spacetime_relative_mass, domain))
end
