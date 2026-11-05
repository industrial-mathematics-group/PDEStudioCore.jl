# ==============================================================================
# --- Parameter serialisation, safe parsing & hashing ---
# ==============================================================================

"""
    val2str(v; top_level::Bool = true)

Converts a value into a Julia-literal-like string (the basis of the parameter hash).
Top-level strings are written unquoted, strings inside containers are quoted, functions become
`"Closure"`, enum values are written as `TypeName.value` and custom structs as
`TypeName(field=value, ...)`.
"""
function val2str(v; top_level::Bool = true)
    if v isa AbstractString && isempty(v)
        return "<empty>"
    elseif isa(v, Function)
        return "Closure"
    elseif isa(v, Val)
        return string(v)
    elseif isa(v, Enum)
        # Enums have no fields, so the generic struct branch would reduce every value to the type name.
        return string(typeof(v).name.name, ".", Symbol(v))
    elseif isa(v, Symbol)
        return repr(v)
    elseif isa(v, AbstractString)
        return top_level ? String(v) : repr(v)
    elseif isa(v, AbstractChar)
        return repr(v)
    elseif isa(v, Number) || isa(v, Type)
        return string(v)
    elseif isa(v, AbstractArray)
        T = eltype(v)
        prefix = T === Any ? "Any" : string(T)
        elements = join([val2str(x; top_level = false) for x in v], ", ")
        # Multidimensional arrays keep their shape (vectors are written without `reshape`).
        return ndims(v) == 1 ? "$(prefix)[$elements]" : "reshape($(prefix)[$elements], $(val2str(size(v))))"
    elseif isa(v, Tuple)
        elements = join([val2str(x; top_level = false) for x in v], ", ")
        return length(v) == 1 ? "($elements,)" : "($elements)"
    elseif isa(v, Dict)
        K, V = keytype(v), valtype(v)
        sorted_keys = sort(collect(keys(v)), by = string)
        elements = join(["$(val2str(k; top_level = false)) => $(val2str(v[k]; top_level = false))" for k in sorted_keys], ", ")
        return "Dict{$K, $V}($elements)"
    else
        type_name = string(typeof(v).name.name)
        fields = propertynames(v)
        isempty(fields) && return type_name
        field_strs = ["$f=$(val2str(getproperty(v, f); top_level = false))" for f in fields]
        return "$type_name(" * join(field_strs, ", ") * ")"
    end
end

# ------------------------------------------------------------------------------
# Safe literal evaluation (str2val never executes arbitrary code)
# ------------------------------------------------------------------------------

struct _NotALiteral <: Exception end

# (`true`/`false` are parsed as Bool literals already and need no entry.)
const _LITERAL_CONSTANTS = Dict{Symbol, Any}(
    :nothing => nothing, :missing => missing,
    :Inf => Inf, :NaN => NaN, :Inf16 => Inf16, :Inf32 => Inf32, :Inf64 => Inf64,
    :NaN16 => NaN16, :NaN32 => NaN32, :NaN64 => NaN64, :pi => π, :π => π, :ℯ => ℯ, :im => im,
)

# Pure functions that may be applied to numeric literals (e.g. "2π", "1/3", "-Inf", "1:10").
const _LITERAL_FUNCTIONS = Dict{Symbol, Function}(
    :+ => +, :- => -, :* => *, :/ => /, :// => //, :^ => ^, :% => %, :(:) => (:),
    :sqrt => sqrt, :exp => exp, :log => log, :log2 => log2, :log10 => log10,
    :sin => sin, :cos => cos, :tan => tan, :abs => abs,
)

function _literal_type(sym::Symbol)
    for mod in (Core, Base, @__MODULE__)
        if isdefined(mod, sym)
            T = getglobal(mod, sym)
            T isa Type && return T
        end
    end
    throw(_NotALiteral())
end

_literal_type(ex::Expr) = (T = _literal(ex); T isa Type ? T : throw(_NotALiteral()))
_literal_type(::Any) = throw(_NotALiteral())

_literal(x::Union{Number, AbstractString, AbstractChar}) = x
_literal(q::QuoteNode) = q.value isa Symbol ? q.value : throw(_NotALiteral())
_literal(sym::Symbol) = haskey(_LITERAL_CONSTANTS, sym) ? _LITERAL_CONSTANTS[sym] : _literal_type(sym)
_literal(::Any) = throw(_NotALiteral())

# The parts of a composite literal. A range is only a literal on its own (e.g. a sweep typed as "1:10"):
# `val2str` never writes ranges into containers, and inside one (`Vector{T}[1:n, …]`, `reshape(1:n, …)`,
# `2 * (1:n)`) it would be expanded before any size check could see it.
function _literal_parts(args)
    parts = map(_literal, args)
    any(p -> p isa AbstractRange, parts) && throw(_NotALiteral())
    return parts
end

function _literal(ex::Expr)
    head, args = ex.head, ex.args
    if head === :vect
        return Base.vect(_literal_parts(args)...)
    elseif head === :tuple
        any(a -> a isa Expr && a.head in (:(=), :kw, :parameters), args) && throw(_NotALiteral())
        return tuple(_literal_parts(args)...)
    elseif head === :ref
        return getindex(_literal_type(args[1]), _literal_parts(args[2:end])...)
    elseif head === :curly
        T = _literal_type(args[1])
        params = _literal_parts(args[2:end])
        # Integer type parameters size types (`NTuple{N, T}`, `Array{T, N}`): huge ones crash the compiler.
        T === Val || all(p -> !(p isa Integer) || abs(p) <= _MAX_TYPE_PARAMETER, params) || throw(_NotALiteral())
        return Core.apply_type(T, params...)
    elseif head === :call
        return _literal_call(args[1], _literal_parts(args[2:end]))
    elseif head === :macrocall && length(args) == 3 && args[3] isa String
        # Integer literals too large for Int64/UInt64 are parsed as `@int128_str "..."` etc.
        T = get(_BIG_LITERAL_MACROS, args[1], nothing)
        T === nothing || return parse(T, args[3])
    end
    throw(_NotALiteral())
end

const _BIG_LITERAL_MACROS = Dict{Any, Type}(
    GlobalRef(Core, Symbol("@int128_str")) => Int128,
    GlobalRef(Core, Symbol("@uint128_str")) => UInt128,
    GlobalRef(Core, Symbol("@big_str")) => BigInt,
)

# Size limits of literals: bits of an exact power (see `_literal_call`), and the number of elements of the
# whole value (ranges are lazy, but hashing writes out every element; see `str2val`).
const _MAX_LITERAL_BITS = 2^20
const _MAX_LITERAL_LENGTH = 10^6
const _MAX_TYPE_PARAMETER = 256  # integer type parameters (except in `Val`)
const _MAX_DIMS = 16             # dimensions of `reshape`
_exact_bits(x::Integer) = ndigits(x; base = 2)
_exact_bits(x::Rational) = max(_exact_bits(numerator(x)), _exact_bits(denominator(x)))
_exact_bits(x::Complex) = max(_exact_bits(real(x)), _exact_bits(imag(x)))
_exact_bits(::Number) = 0  # fixed-size (or fixed-precision) results

# Number of elements of a parsed literal, counting the elements of (lazy) ranges.
# Lazy arrays (ranges, reshaped ranges) are counted by `length` before anything is iterated, and the sum stops as
# soon as it exceeds `limit`, so neither huge lazy values nor `Int` overflow get through. Returns at most `limit + 1`.
function _literal_size(x, limit::Integer = _MAX_LITERAL_LENGTH)
    x isa AbstractArray && length(x) > limit && return limit + 1
    x isa Pair && return _sum_sizes((x.first, x.second), limit)
    x isa Union{Tuple, AbstractArray, AbstractDict} || return 1
    return max(1, _sum_sizes(x, limit))
end

function _sum_sizes(items, limit::Integer)
    total = 0
    for item in items
        total += _literal_size(item, limit - total)
        total > limit && return limit + 1
    end
    return total
end

function _literal_call(f, values::Vector)
    if f === :(=>) && length(values) == 2
        return values[1] => values[2]
    elseif f === :reshape && length(values) == 2 && values[1] isa AbstractVector &&
           values[2] isa Tuple{Vararg{Integer}}
        # (overflow-checked: wrapped dimensions could otherwise pass for an empty array)
        dims = values[2]
        (length(dims) <= _MAX_DIMS && all(d -> 0 <= d <= _MAX_LITERAL_LENGTH, dims) &&
         foldl(Base.checked_mul, dims; init = 1) <= _MAX_LITERAL_LENGTH) || throw(_NotALiteral())
        return reshape(values[1], values[2])
    elseif f isa Symbol && haskey(_LITERAL_FUNCTIONS, f) && all(v -> v isa Number, values)
        # Exact powers and ranges grow with their arguments: a file must not be able to request huge ones.
        # Ranges are capped here, where they are built (they are only literals on their own, see `_literal_parts`).
        # (A division, not a product: the product of the exponent and the bits overflows for huge exponents.)
        if f === :^ && length(values) == 2
            bits = _exact_bits(values[1])
            bits > 0 && abs(values[2]) > _MAX_LITERAL_BITS / bits && throw(_NotALiteral())
        end
        result = _LITERAL_FUNCTIONS[f](values...)
        f === :(:) && Base.checked_length(result) > _MAX_LITERAL_LENGTH && throw(_NotALiteral())
        return result
    end
    T = _literal_type(f)
    # Only plain dictionary types: e.g. `EnvDict()` would return the live `ENV`.
    if (T <: Dict || T <: IdDict) && all(v -> v isa Pair, values)
        return T(values...)
    elseif T <: Val && isempty(values)
        return T()
    elseif T === Symbol && length(values) == 1 && values[1] isa AbstractString
        return Symbol(values[1])
    elseif T <: Number && length(values) == 1 && values[1] isa Number
        return T(values[1])
    end
    throw(_NotALiteral())
end

"""
    str2val(val_str::AbstractString)

Inverse of [`val2str`](@ref): parses literals (numbers, strings, symbols, types, tuples, typed or
untyped vectors, `reshape(T[...], dims)`, `Dict{K, V}(...)`, `Val{...}()`, and arithmetic on numbers
such as `2π` or `1/3`).
Anything else is returned as a (cleaned) string. Arbitrary code is never evaluated, and values beyond the size
limits (exact powers above 2^20 bits, more than 10^6 elements in total, ranges included) are returned as strings.
"""
function str2val(val_str::AbstractString)
    s = strip(String(val_str))  # a plain String: the parser cannot iterate every AbstractString (e.g. lazy CSV strings)
    (s == "<empty>" || isempty(s)) && return ""
    try
        value = _literal(Meta.parse(s))
        _literal_size(value) > _MAX_LITERAL_LENGTH && throw(_NotALiteral())
        return value
    catch e
        e isa InterruptException && rethrow()
        return replace(s, r"^\"|\"$" => "")
    end
end

# Normalisation used before saving and hashing: strings are kept verbatim (they are never
# re-interpreted as code), closures become "Closure", other values round-trip through val2str.
# Known limitation: `nothing`/`missing` *inside* containers come back as the types `Nothing`/`Missing`
# (or the container as a string). The hashes would not change (`val2str(nothing) == val2str(Nothing)`), but the
# stored "params" of existing files would no longer match newly normalised filters (`find_sim_data`, deletion).
_normalize_param(v::AbstractString) = String(v)
_normalize_param(v::Union{Nothing, Missing}) = v  # would otherwise become the types `Nothing`/`Missing`
_normalize_param(v) = str2val(val2str(v))
_normalize_params(params) = ParamDict(Symbol(k) => _normalize_param(v) for (k, v) in params)

"""
    calculate_hash(params::AbstractDict)

SHA-256 hash (hex string) of the parameters, computed from the sorted `key => val2str(value)` pairs.
"""
function calculate_hash(params::AbstractDict)
    sorted_keys = sort!(collect(keys(params)), by = string)
    to_hash = join(["$k => $(val2str(params[k]))" for k in sorted_keys], ", ")
    return bytes2hex(sha256(to_hash))
end

"""
    get_clean_params(params::AbstractDict)
    get_clean_params(data::AbstractSimData)

Returns the normalised copy of the parameters, exactly as it is stored on disk and hashed.
"""
get_clean_params(params::AbstractDict) = _normalize_params(params)
get_clean_params(sim_data::AbstractSimData) = get_clean_params(sim_data.params)

"""
    print_clean_params(data)

Prints the normalised parameters (of a dictionary or a dataset) in alphabetical order and returns them.
"""
function print_clean_params(data)
    clean_dict = get_clean_params(data)
    println("\n--- Cleaned Parameters ---")
    for (k, v) in sort(collect(clean_dict), by = x -> string(x[1]))
        println("  $k => $v")
    end
    println("--------------------------\n")
    return clean_dict
end
