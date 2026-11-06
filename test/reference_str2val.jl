# The literal parser of PDEStudioCore before the allowlist (main_dev, Nov 2026), kept verbatim as the reference of
# `test_str2val_differential.jl`: every literal the old parser accepted must parse to the same value now, except the
# documented differences. Only its module lookup is pointed at PDEStudioCore (it was `@__MODULE__`).
module OldStr2Val
using PDEStudioCore
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
    for mod in (Core, Base, PDEStudioCore)
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
end
