# ==============================================================================
# --- Statistic layers: simulation -> reference -> post-processing ---
# ==============================================================================
# Every statistic of a dataset belongs to one layer, by what produced it:
#   :simulation   the solver's output (`:Solution` and what the solver attached: volumes, run time, …), statistics added
#                 by hand, and the registered statistics of the data alone (`calc_stat` without the reference argument)
#   :reference    the registered statistics that use the reference (`calc_stat(::Val{name}, coords, u, ana, domain)`)
#   :postprocess  what post-processors added
# A layer is computed from the ones above it: when the simulation or reference layer changes (a statistic evaluated,
# replaced or removed, or another reference), the post-processing layer is dropped (and the post-processors run
# again). Names are unique across the layers.
#
# The records are reserved entries of the dataset's metadata, saved with the data and carried with it:
#   :stat_records => Dict(
#       :solution   => SHA-256 (hex) of the solution the records describe,
#       :params     => the hash of the parameters they were evaluated with (references and post-processors get them),
#       :basis      => the fingerprint of the statistics above the post-processing layer (`_upstream_basis`, set on
#                      every write): a post-processor's record holds the one it ran on,
#       :simulation => Dict(:evaluated => names, :empty => names),       # the registered statistics of the data
#       :reference  => Dict(:record => the reference (`_reference_record`), :evaluated => names, :empty => names),
#       :legacy     => names,   # (a file of an earlier version: statistics of unknown origin, taken over by the pass
#                                  # that evaluates them again: the statistics pass or a post-processor)
#       :legacy_derived => names)  # (those of them the statistics pass of that version evaluated: derived from the
#                                  # solution and parameters, dropped when these change)
#   :postprocessed => Dict(name => Dict(the post-processor's identity…, :keys => the statistics it added))
# `:evaluated` lists what the statistics pass evaluated; `:empty` those of them without a result (all NaN: dropped).

const _LAYERS = (:simulation, :reference, :postprocess)

_names(v) = v isa AbstractVector || v isa Tuple || v isa AbstractSet ? sort!(unique!(Symbol[Symbol(x) for x in v])) : Symbol[]
_empty_layer() = Dict{Symbol, Any}(:evaluated => Symbol[], :empty => Symbol[])

function _layer_record(r)
    r isa AbstractDict || return nothing
    d = Dict{Symbol, Any}(Symbol(k) => v for (k, v) in r)
    d[:evaluated] = _names(get(d, :evaluated, nothing))
    d[:empty] = _names(get(d, :empty, nothing))
    return d
end

# The statistic records of a metadata dict, as a normalised copy (missing parts empty; `:reference` only once the
# reference layer was evaluated)
function _stat_records(md::AbstractDict)
    r = get(md, :stat_records, nothing)
    r = r isa AbstractDict ? Dict{Symbol, Any}(Symbol(k) => v for (k, v) in r) : Dict{Symbol, Any}()
    out = Dict{Symbol, Any}(:simulation => something(_layer_record(get(r, :simulation, nothing)), _empty_layer()),
                            :legacy => _names(get(r, :legacy, nothing)),
                            :legacy_derived => _names(get(r, :legacy_derived, nothing)))
    s = get(r, :solution, nothing)
    s isa AbstractString && (out[:solution] = String(s))
    for k in (:params, :basis)
        h = get(r, k, nothing)
        h isa AbstractString && (out[k] = String(h))
    end
    ref = _layer_record(get(r, :reference, nothing))
    if ref !== nothing
        rec = get(ref, :record, "")
        ref[:record] = rec isa AbstractString ? String(rec) : ""
        out[:reference] = ref
    end
    return out
end

# The post-processing records of a metadata dict: name => record (a copy; `:keys` normalised where present)
function _post_records(md::AbstractDict)
    done = get(md, :postprocessed, nothing)
    out = Dict{Symbol, Dict{Symbol, Any}}()
    done isa AbstractDict || return out
    for (k, v) in done
        v isa AbstractDict || continue
        rec = Dict{Symbol, Any}(Symbol(a) => b for (a, b) in v)
        haskey(rec, :keys) && (rec[:keys] = _names(rec[:keys]))
        out[Symbol(k)] = rec
    end
    return out
end
_post_keys(posts::AbstractDict) = sort!(unique!(Symbol[k for rec in values(posts) for k in _names(get(rec, :keys, nothing))]))

"""
    stat_layer(data::AbstractSimData, name::Symbol) -> Symbol

The layer the statistic `name` of `data` belongs to: `:simulation` (the solution, what the solver attached, e.g. run
time or volumes, statistics added by hand with [`add_stat!`](@ref), and the registered statistics of the data alone),
`:reference` (the registered statistics that use the reference) or `:postprocess` (what post-processors added). The
layers build on each other, simulation → reference → post-processing: when the statistics of a layer change, the
layers below are evaluated again (see "Statistics" in the manual). A `KeyError` if `data` has no statistic `name`.
"""
function stat_layer(data::AbstractSimData, name::Symbol)
    name === :Solution && return :simulation
    haskey(_raw_stats(data), name) || throw(KeyError(name))
    md = data.metadata
    r = _stat_records(md)
    haskey(r, :reference) && name in r[:reference][:evaluated] && return :reference
    name in _post_keys(_post_records(md)) && return :postprocess
    return :simulation
end

"""
    layer_stats(data::AbstractSimData, layer::Symbol) -> Vector{Symbol}

The names of the statistics of `data` in `layer` (`:simulation`, `:reference` or `:postprocess`, see
[`stat_layer`](@ref)), sorted; `:Solution` belongs to `:simulation`.
"""
function layer_stats(data::AbstractSimData, layer::Symbol)
    layer in _LAYERS || throw(ArgumentError("layer :$layer: the layers are :simulation, :reference and :postprocess"))
    return sort!(Symbol[k for k in keys(data.stats) if stat_layer(data, k) === layer])
end

# What a registered statistic is, by its `calc_stat` methods: `:data` (`calc_stat(::Val{name}, fixed_coords, u, domain)`,
# no reference: the simulation layer), `:reference` (`calc_stat(::Val{name}, fixed_coords, u, ana, domain)`) or `:none`
# (no method: an error). In the latest world: methods defined after the caller started count.
function _stat_kind(name::Symbol)
    return Base.invokelatest() do
        # (by the calls the statistics pass makes: a method applicable to them, e.g. also a vararg one; not a generic
        # method for another domain type, nor the generic fallback, which only reports the missing method)
        !isempty(methods(calc_stat, Tuple{Val{name}, Any, Any, DomainInfo})) ? :data :
        any(m -> m !== _CALC_STAT_FALLBACK, methods(calc_stat, Tuple{Val{name}, Any, Any, Any, DomainInfo})) ? :reference : :none
    end
end
_is_data_stat(name::Symbol) = _stat_kind(name) === :data

# The SHA-256 digest of the solution of a dataset: every value of its axes (or times and positions) and of `u`, each
# array with its length (`Base.hash` samples large arrays and would miss a change of a few entries)
function _solution_digest(d::AbstractSimData)
    ctx = SHA.SHA256_CTX()
    arrays = d isa ESimData ? (d.axes..., d.u) : Iterators.flatten(((d.t,), d.x, d.u))   # (Lagrangian: one array per step)
    foreach(a -> _digest_array!(ctx, a), arrays)
    return SHA.digest!(ctx)
end
function _digest_array!(ctx, a)
    SHA.update!(ctx, reinterpret(UInt8, [length(a)]))
    SHA.update!(ctx, !isbitstype(eltype(a)) ? codeunits(repr(a)) :   # (e.g. BigFloat: its text)
                     reinterpret(UInt8, a isa Array ? vec(a) : collect(a)))
    return ctx
end
_solution_hex(d::AbstractSimData) = bytes2hex(_solution_digest(d))

# The fingerprint of a statistic of a dataset: the dimensions it keeps, its shape and its values (to tell whether it
# changed: a post-processor's guard, `_upstream_basis`)
function _stat_fingerprint(data::AbstractSimData, k::Symbol)
    ctx = SHA.SHA256_CTX()
    SHA.update!(ctx, codeunits(string(k, '\0', repr(get(data.domain.stat_registry, k, nothing)), '\0')))
    SHA.update!(ctx, _value_digest(_raw_stats(data)[k]))
    return SHA.digest!(ctx)
end

# The fingerprint of the statistics above the post-processing layer (all but the post-processors', including those of
# unknown origin, `:legacy`, which count as the simulation layer): a post-processor's record is valid while it is the
# one it ran on
function _upstream_basis(data::AbstractSimData)
    md = data.metadata
    skip = _post_keys(_post_records(md))
    ctx = SHA.SHA256_CTX()
    foreach(k -> SHA.update!(ctx, _stat_fingerprint(data, k)), sort!([k for k in keys(_raw_stats(data)) if !(k in skip)]))
    return bytes2hex(SHA.digest!(ctx))
end

# Writes the current basis into the records (every full write of a dataset that has statistic records)
function _stamp_basis!(data::AbstractSimData)
    (haskey(data.metadata, :stat_records) || haskey(data.metadata, :postprocessed)) || return data
    r = _stat_records(data.metadata)
    r[:basis] = _upstream_basis(data)
    data.metadata[:stat_records] = r
    return data
end

# What a statistic's value is, independent of the names a session imported (`string(typeof(v))` would print
# `StaticArraysCore.SVector` or `SVector`): scalar (`s<components>`), array (`a<dims>[element]`), number type
_type_kind(T) = T <: SVector ? string("s", length(T), _type_kind(eltype(T))) :
                T <: AbstractArray ? string("a", ndims(T), "[", _type_kind(eltype(T)), "]") :
                T isa DataType ? string(nameof(T)) : "?"
_kind_text(v) = _type_kind(typeof(v))

# The digest of the value of a statistic, with its shape
function _value_digest(v)
    ctx = SHA.SHA256_CTX()
    SHA.update!(ctx, codeunits(_kind_text(v) * "\0"))   # (a scalar is not a one-element series)
    v isa AbstractArray && SHA.update!(ctx, reinterpret(UInt8, collect(Int, size(v))))
    if v isa AbstractArray && eltype(v) <: AbstractArray && !(eltype(v) <: SVector)   # (per-particle fields)
        foreach(a -> _digest_array!(ctx, a), v)
    elseif v isa AbstractArray
        _digest_array!(ctx, v)
    else
        SHA.update!(ctx, codeunits(repr(v)))
    end
    return SHA.digest!(ctx)
end

# The records of a file written by an earlier version ("evaluated_stats", post-processing records without the
# statistics they added), read as records of this version without guessing layers (that would depend on which
# `calc_stat` methods are loaded): its statistics evaluated by the statistics pass, and if a post-processor ran its
# other statistics, are `:legacy`, of unknown origin. Nothing of them is dropped: the statistics pass evaluates the
# registered ones again and takes them over (once), a post-processor takes over the ones it changes. Its solution
# digest and parameter hash are stamped when the data is loaded (`_stamp_records!`).
function _migrate_records!(md::Dict{Symbol, Any}, file)
    if haskey(md, :stat_records)
        r = _stat_records(md)
        haskey(r, :basis) && return md
        # (records without a basis were written before it existed, by the unreleased 0.10.0 snapshot before #70, whose
        # migration guessed layers from the methods loaded: read like an earlier version's, their evaluated statistics
        # of unknown origin, taken over again)
        stored = setdiff(haskey(file, "stat_keys") ? _names(file["stat_keys"]) : Symbol[], [:Solution])
        evaluated = intersect(union(r[:simulation][:evaluated], get(get(r, :reference, Dict{Symbol, Any}()), :evaluated, Symbol[])), stored)
        md[:stat_records] = Dict{Symbol, Any}(:simulation => _empty_layer(), :legacy => _names(union(r[:legacy], evaluated)),
                                              :legacy_derived => _names(union(r[:legacy_derived], evaluated)))
        return md
    end
    has_posts = !isempty(_post_records(md))
    (haskey(file, "evaluated_stats") || has_posts) || return md
    evaluated = haskey(file, "evaluated_stats") ? _names(file["evaluated_stats"]) : Symbol[]
    stored = setdiff(haskey(file, "stat_keys") ? _names(file["stat_keys"]) : Symbol[], [:Solution])
    legacy = union(intersect(evaluated, stored), has_posts ? setdiff(stored, evaluated) : Symbol[])
    md[:stat_records] = Dict{Symbol, Any}(:simulation => _empty_layer(), :legacy => _names(legacy),
                                          :legacy_derived => _names(intersect(evaluated, stored)))
    return md
end

_params_hash(data::AbstractSimData) = calculate_hash(data.params)

# Stamps the solution digest and the parameter hash into records that lack them (records of an earlier version, read
# with the data they describe: `_load_key`), so a change made to the data afterwards is recognised
function _stamp_records!(data::AbstractSimData)
    md = data.metadata
    haskey(md, :stat_records) || return data
    r = _stat_records(md)
    haskey(r, :solution) && haskey(r, :params) && return data
    haskey(r, :solution) || (r[:solution] = _solution_hex(data))
    haskey(r, :params) || (r[:params] = _params_hash(data))
    md[:stat_records] = r
    return data
end

# Drops the statistics whose records describe other data than the dataset's, with their records: for another solution
# the registered statistics of the simulation layer and the reference and post-processing layers, for other parameters
# (the reference and the post-processors get them) the reference and post-processing layers. `same`: whether the data is
# the one the records were read with, for records without a digest. The statistics of an earlier version's
# post-processor (`:legacy`, unknown which) stay listed. Returns whether it dropped.
function _drop_stale_layers!(data::AbstractSimData; same::Bool = true)
    md = data.metadata
    (haskey(md, :stat_records) || haskey(md, :postprocessed)) || return false
    r = _stat_records(md)
    digest, params = get(r, :solution, nothing), get(r, :params, nothing)
    solution_ok = digest === nothing ? same : digest == _solution_hex(data)
    params_ok = params === nothing ? same : params == _params_hash(data)
    solution_ok && params_ok && return false
    raw = _raw_stats(data)
    derived = union(haskey(r, :reference) ? r[:reference][:evaluated] : Symbol[], _post_keys(_post_records(md)))
    solution_ok || (derived = union(derived, r[:simulation][:evaluated]))
    derived = union(derived, r[:legacy_derived])   # (an earlier version's statistics: unknown which depend on what)
    foreach(k -> delete!(raw, k), derived)
    kept = Dict{Symbol, Any}(:simulation => solution_ok ? r[:simulation] : _empty_layer(),
                             :legacy => setdiff(r[:legacy], derived))
    md[:stat_records] = kept
    delete!(md, :postprocessed)
    return true
end

# --- Planning the statistics pass -------------------------------------------------------------------------------

# What the statistics pass does for a dataset: the registered statistics of each layer to evaluate (`due`) and the
# recorded ones to drop (`stale`: moved to the other layer, or no longer registered when the layer is evaluated afresh), whether the reference layer is
# evaluated afresh (`fresh`: another reference, or all of it again), whether the post-processing layer goes
# (`cascade`: the layers above change: a statistic evaluated, replaced or removed), the outcome to report and an error
# (a registered name taken by a statistic of another layer).
Base.@kwdef struct _StatPlan
    sim_due::Vector{Symbol} = Symbol[]
    sim_stale::Vector{Symbol} = Symbol[]
    ref_due::Vector{Symbol} = Symbol[]
    ref_stale::Vector{Symbol} = Symbol[]
    fresh::Bool = false
    cascade::Bool = false
    status::Symbol = :cached
    error::Union{Nothing, String} = nothing
end

_has_work(p::_StatPlan) = !isempty(p.sim_due) || !isempty(p.sim_stale) || !isempty(p.ref_due) || !isempty(p.ref_stale) || p.fresh

# How the reference `record` differs from the one the reference layer was evaluated with (`stored`): `:none`,
# `:reference` (another reference, or an unknown one: "" on either side) or `:code` (the same reference, its file or
# package version changed; with `ignore_file` only the package version counts)
function _reference_change(stored::AbstractString, record::AbstractString; ignore_file::Bool = false)
    (isempty(stored) || isempty(record)) && return :reference
    stored == record && return :none
    parts(r) = Dict(split(p, "="; limit = 2) for p in split(r, "; ") if occursin("=", p))
    a, b = parts(stored), parts(record)
    get(a, "name", "") == get(b, "name", "") || return :reference
    ignore_file && (delete!(a, "file"); delete!(b, "file"))
    return a == b ? :none : :code
end

# `records`/`posts`: the dataset's records; `present`: its statistics; `dims`: the kept dimensions it holds them for (its
# registry); `registry`: the global one; `reference`: the reference record, `nothing` without a reference (the reference
# layer is left as it is). `force`: everything evaluated again. `on_changed`: what a changed reference (same name,
# other code) does: `:warn` keeps the reference layer (`:outdated`, or `:refreshed`: all of it again if statistics are
# missing), `:recompute` evaluates it again, `:ignore` only looks at the package version.
function _plan_stats(records::AbstractDict, posts::AbstractDict, present, dims::AbstractDict, registry::AbstractDict,
                     reference::Union{Nothing, AbstractString}; force::Bool = false, on_changed::Symbol = :warn)
    present = Set{Symbol}(present)
    registered = sort!(Symbol[k for k in keys(registry) if k !== :Solution])
    kinds = Dict(n => _stat_kind(n) for n in registered)
    missing_method = sort!([n for (n, k) in kinds if k === :none])
    isempty(missing_method) || return _StatPlan(status = :failed, error =
        "the statistic :$(first(missing_method)) is registered (`register_stat!`), but has no `calc_stat` method (neither " *
        "`calc_stat(::Val{:$(first(missing_method))}, fixed_coords, u, domain)` nor one with `ana` before `domain`): a " *
        "missing `include`, a typo in the name, or a preset loaded later?")
    data_names = filter(n -> kinds[n] === :data, registered)
    ref_names = setdiff(registered, data_names)
    moved(n) = get(dims, n, nothing) != registry[n]
    needs(layer, n) = force || !(n in layer[:evaluated]) || (!(n in layer[:empty]) && !(n in present)) || moved(n)

    # (statistics that aren't registered any more stay, still valid, until their layer is evaluated afresh: `force`, or
    # for the reference layer another reference; a pass with a smaller registry doesn't remove what others evaluated)
    sim = records[:simulation]
    sim_stale = force ? union(setdiff(sim[:evaluated], data_names), setdiff(records[:legacy_derived], registered)) : Symbol[]
    sim_due = filter(n -> needs(sim, n), data_names)

    ref = get(records, :reference, nothing)
    ref_due, ref_stale, fresh, status = Symbol[], Symbol[], false, :ran
    if reference !== nothing
        change = ref === nothing ? :reference : _reference_change(ref[:record], reference; ignore_file = on_changed === :ignore)
        keep = change === :code && on_changed !== :recompute && !force
        if change === :none || keep
            ref_stale = force ? setdiff(ref[:evaluated], ref_names) : Symbol[]
            ref_due = filter(n -> needs(ref, n), ref_names)
            keep && (isempty(ref_due) ? (status = :outdated) : (fresh = true; status = :refreshed))
        else
            fresh = true
        end
        if fresh
            ref_due = copy(ref_names)
            ref_stale = ref === nothing ? Symbol[] : setdiff(ref[:evaluated], ref_names)
        end
    end

    # (a statistic that moved to the other layer leaves the record of the one it was in)
    ref === nothing || (ref_stale = union(ref_stale, intersect(sim_due, ref[:evaluated])))
    sim_stale = union(sim_stale, intersect(ref_due, sim[:evaluated]))

    # names are unique across the layers: a registered statistic may only replace its own layer's value (or one of the
    # other registered layer, when it moved between them)
    recorded = union(sim[:evaluated], ref === nothing ? Symbol[] : ref[:evaluated])
    post_keys = _post_keys(posts)
    for n in union(sim_due, ref_due)
        (n in present && !(n in recorded) && !(n in records[:legacy])) || continue   # (a legacy statistic is taken over)
        owner = n in post_keys ? "the post-processor that added it" : "the solver, or `add_stat!`"
        return _StatPlan(status = :failed, error =
            "the statistic :$n is registered, but the dataset has a statistic :$n from $owner; statistic names are " *
            "unique across the layers (simulation, reference, post-processing): rename one of them")
    end

    # (any change of the layers above, also an added statistic, is a new state for the post-processors)
    work = !isempty(sim_due) || !isempty(sim_stale) || !isempty(ref_due) || !isempty(ref_stale) || fresh
    cascade = work
    work || status === :outdated || (status = :cached)
    return _StatPlan(; sim_due, sim_stale, ref_due, ref_stale, fresh, cascade, status)
end
