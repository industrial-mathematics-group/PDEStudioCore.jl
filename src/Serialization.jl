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
# Safe literal parsing (str2val never executes code)
# ------------------------------------------------------------------------------
# `str2val` reads values from files (CSV configs, presets) and the editors, so it must neither run code nor let a
# short text cost unbounded time or memory. It evaluates a fixed grammar: the literals `val2str` writes, plus
# arithmetic on numbers ("2π", "1/3", "1e-3") and ranges as whole values ("1:10"). Types come from an allowlist
# (the types `val2str` writes for parameters), and what it builds is bounded: the size of types (parameters, nested
# ones and the elements of static arrays: compiling for a huge type can crash Julia), the bits of exact numbers and
# the exponent of BigFloats, the dimensions of arrays, the nesting of the text and of the literal (every level
# compiles for a new type), and the number of elements of the whole value (and of its digits, for ranges).

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
# ... of which these are only applied to fixed-size numbers: their cost grows with the size of a BigFloat/BigInt
# argument (e.g. the argument reduction of `sin` needs a precision of about the exponent).
const _FIXED_SIZE_FUNCTIONS = (:sqrt, :exp, :log, :log2, :log10, :sin, :cos, :tan)

# The types a literal may name, build or contain: numbers, text, the containers `val2str` writes and the static
# arrays of StaticArrays. Anything else (e.g. `EnvDict`, `OneTo`, types of other packages) is not a literal.
const _LITERAL_TYPES = Dict{Symbol, Any}(
    :Bool => Bool, :Int8 => Int8, :Int16 => Int16, :Int32 => Int32, :Int64 => Int64, :Int128 => Int128,
    :UInt8 => UInt8, :UInt16 => UInt16, :UInt32 => UInt32, :UInt64 => UInt64, :UInt128 => UInt128,
    :BigInt => BigInt, :Int => Int, :UInt => UInt, :Float16 => Float16, :Float32 => Float32, :Float64 => Float64,
    :BigFloat => BigFloat, :Rational => Rational, :Complex => Complex, :ComplexF16 => ComplexF16,
    :ComplexF32 => ComplexF32, :ComplexF64 => ComplexF64, :Irrational => Irrational, :Number => Number,
    :Real => Real, :AbstractFloat => AbstractFloat, :Integer => Integer, :Signed => Signed, :Unsigned => Unsigned,
    :AbstractIrrational => AbstractIrrational, :Char => Char, :AbstractChar => AbstractChar, :String => String,
    :AbstractString => AbstractString, :Symbol => Symbol, :Any => Any, :Nothing => Nothing, :Missing => Missing,
    :Union => Union, :Type => Type, :DataType => DataType, :UnionAll => UnionAll,
    :Function => Function, :Tuple => Tuple, :NTuple => NTuple, :Pair => Pair, :Val => Val,
    :Vector => Vector, :Matrix => Matrix, :Array => Array, :AbstractVector => AbstractVector,
    :AbstractMatrix => AbstractMatrix, :AbstractArray => AbstractArray, :Dict => Dict,
    :AbstractDict => AbstractDict, :SVector => SVector, :SMatrix => SMatrix, :SArray => SArray,
    :MVector => MVector, :MMatrix => MMatrix, :MArray => MArray, :StaticVector => StaticVector,
    :StaticMatrix => StaticMatrix, :StaticArray => StaticArray, :SA => SA, :SA_F64 => SA_F64, :SA_F32 => SA_F32,
)

const _MAX_LITERAL_BITS = 2^20     # bits of an exact number (Integer, Rational, Complex) and BigFloat exponents
const _MAX_LITERAL_LENGTH = 10^6   # elements of the whole value (ranges included: hashing writes every element)
const _MAX_RANGE_BITS = 2^24       # elements × bits of a range of BigInts/BigFloats (hashing writes every element)
const _MAX_TYPE_SIZE = 1024        # size of a type: parameters, nested ones and static array elements counted
const _MAX_DIMS = 16               # dimensions of arrays and array types
const _MAX_DEPTH = 32              # nesting of brackets in the text and of expressions in the parsed literal
const _MAX_OPERATORS = 1024        # operator characters between two separators of the text (see `_too_nested`)

_exact_bits(x::Integer) = ndigits(x; base = 2)
_exact_bits(x::Rational) = max(_exact_bits(numerator(x)), _exact_bits(denominator(x)))
_exact_bits(x::Complex) = max(_exact_bits(real(x)), _exact_bits(imag(x)))
_exact_bits(x::BigFloat) = isfinite(x) && !iszero(x) ? abs(exponent(x)) : 0   # converting it exactly costs that
_exact_bits(::Number) = 0  # fixed-size results

# A parsed or computed number within the size limits
_checked_number(x::Number) = _exact_bits(x) <= _MAX_LITERAL_BITS ? x : throw(_NotALiteral())

_is_fixed_size(::Union{BigInt, BigFloat}) = false
_is_fixed_size(x::Rational) = _is_fixed_size(numerator(x))
_is_fixed_size(x::Complex) = _is_fixed_size(real(x)) && _is_fixed_size(imag(x))
_is_fixed_size(::Number) = true

# The size of a type: its parameters, nested ones included, and the elements of static arrays, whose number is a
# value parameter (`SVector{64, SVector{64, Int}}` holds 4096 numbers, and compiling for it costs that much). Also for
# static array types with a free element type (`SArray{Tuple{1000, 1000}}`). Returns at most `limit + 1`.
function _type_size(T, limit::Integer = _MAX_TYPE_SIZE)
    if T isa Union
        a = _type_size(T.a, limit)
        return a > limit ? a : min(a + _type_size(T.b, limit - a), limit + 1)
    end
    T isa UnionAll && return _type_size(Base.unwrap_unionall(T), limit)
    T isa DataType || return 1
    total = 1
    for p in T.parameters
        total += _type_size(p, limit - total)
        total > limit && return limit + 1
    end
    if T.name.wrapper <: StaticArray && !isempty(T.parameters) && T.parameters[1] isa DataType &&
       T.parameters[1] <: Tuple
        n = 1
        for d in T.parameters[1].parameters
            d isa Integer || return total   # (a free size)
            n *= max(d, 0)
            n > limit && return limit + 1
        end
        element = length(T.parameters) >= 2 ? _type_size(T.parameters[2], limit) : 1
        n * element > limit - total && return limit + 1
        total += n * element
    end
    return total
end

# A type that may be named or built: bounded size, and arrays with at most `_MAX_DIMS` dimensions.
function _checked_type(T)
    _type_size(T) <= _MAX_TYPE_SIZE || throw(_NotALiteral())
    if T isa DataType && T <: AbstractArray
        N = _array_ndims(T)
        N isa Integer && !(0 <= N <= _MAX_DIMS) && throw(_NotALiteral())
    end
    return T
end
_array_ndims(::Type{<:AbstractArray{<:Any, N}}) where {N} = N
_array_ndims(::Type) = nothing

function _literal_type(sym::Symbol, depth::Int = 0)
    T = get(_LITERAL_TYPES, sym, nothing)
    T === nothing && throw(_NotALiteral())
    return T
end
_literal_type(ex::Expr, depth::Int = 0) = (T = _literal(ex, depth); T isa Type ? T : throw(_NotALiteral()))
_literal_type(::Any, depth::Int = 0) = throw(_NotALiteral())

# (`depth`: how deep in the expression the part is; every level compiles for a new type, see `_MAX_DEPTH`)
_literal(x::Number, depth::Int = 0) = _checked_number(x)
_literal(x::Union{AbstractString, AbstractChar}, depth::Int = 0) = x
_literal(q::QuoteNode, depth::Int = 0) = q.value isa Symbol ? q.value : throw(_NotALiteral())
_literal(sym::Symbol, depth::Int = 0) = haskey(_LITERAL_CONSTANTS, sym) ? _LITERAL_CONSTANTS[sym] : _literal_type(sym)
_literal(::Any, depth::Int = 0) = throw(_NotALiteral())

# The parts of a composite literal. A range is only a literal on its own (e.g. a sweep typed as "1:10"):
# `val2str` never writes ranges into containers, and inside one (`Vector{T}[1:n, …]`, `reshape(1:n, …)`,
# `2 * (1:n)`) it would be expanded before any size check could see it.
function _literal_parts(args, depth::Int)
    parts = map(a -> _literal(a, depth), args)
    any(p -> p isa AbstractRange, parts) && throw(_NotALiteral())
    return parts
end

function _literal(ex::Expr, depth::Int = 0)
    depth < _MAX_DEPTH || throw(_NotALiteral())
    head, args, inner = ex.head, ex.args, depth + 1
    if head === :vect
        return Base.vect(_literal_parts(args, inner)...)
    elseif head === :tuple
        any(a -> a isa Expr && a.head in (:(=), :kw, :parameters), args) && throw(_NotALiteral())
        return tuple(_literal_parts(args, inner)...)
    elseif head === :ref
        T = _checked_type(_literal_type(args[1], inner))
        return getindex(T, _literal_parts(args[2:end], inner)...)
    elseif head === :curly
        T = _literal_type(args[1], inner)
        params = _literal_parts(args[2:end], inner)
        # Integer parameters size types (`NTuple{N, T}`): bound them before the type is built (`Val` is inert).
        T === Val || all(p -> !(p isa Integer) || abs(p) <= _MAX_TYPE_SIZE, params) || throw(_NotALiteral())
        return _checked_type(Core.apply_type(T, params...))
    elseif head === :call
        return _literal_call(args[1], _literal_parts(args[2:end], inner), inner)
    elseif head === :macrocall && length(args) == 3 && args[3] isa String
        # Integer literals too large for Int64/UInt64 are parsed as `@int128_str "..."` etc.
        T = get(_BIG_LITERAL_MACROS, args[1], nothing)
        T === nothing || return _checked_number(parse(T, args[3]))
    end
    throw(_NotALiteral())
end

const _BIG_LITERAL_MACROS = Dict{Any, Type}(
    GlobalRef(Core, Symbol("@int128_str")) => Int128,
    GlobalRef(Core, Symbol("@uint128_str")) => UInt128,
    GlobalRef(Core, Symbol("@big_str")) => BigInt,
)

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

# The length of a range without overflow (`checked_length` has no method for Rational steps).
_range_length(r::AbstractRange{<:Rational}) = length(r)
_range_length(r::AbstractRange) = Base.checked_length(r)

# A range built from `values` within the size limits: its length, and for ranges of BigInts/BigFloats (whose hash
# text holds every element, each as long as its number) also the length times the bits of the endpoints.
function _checked_range(r::AbstractRange, values)
    n = _range_length(r)
    n <= _MAX_LITERAL_LENGTH || throw(_NotALiteral())
    all(_is_fixed_size, values) && return r
    bits = maximum(v -> max(_exact_bits(v), v isa BigFloat ? precision(v) : 64), values)
    n <= _MAX_RANGE_BITS ÷ bits || throw(_NotALiteral())
    return r
end

# Whether the text nests too deep for `Meta.parse` (which can overflow the stack on deep nesting): brackets nested
# more than `_MAX_DEPTH` levels, or more than `_MAX_OPERATORS` operator characters between two separators (`1-1-1…`,
# `- - -1`). Outside of string literals; Char literals count, which only overestimates. `val2str` writes elements
# separated by commas, each with a few operators.
function _too_nested(s::AbstractString)
    depth, operators, quoted, escaped = 0, 0, false, false
    for c in s
        if quoted
            escaped ? (escaped = false) : c == '\\' ? (escaped = true) : c == '"' && (quoted = false)
        elseif c == '"'
            quoted = true
        elseif c in ('(', '[', '{')
            depth += 1
            depth > _MAX_DEPTH && return true
            operators = 0
        elseif c in (')', ']', '}', ',', ';', '\n')
            c in (')', ']', '}') && (depth -= 1)
            operators = 0
        elseif c in _OPERATOR_CHARS
            operators += 1
            operators > _MAX_OPERATORS && return true
        end
    end
    return false
end
const _OPERATOR_CHARS = Set("+-*/\\^%<>=!~&|:?√∛∜¬÷⊻")

function _literal_call(f, values::Vector, depth::Int = 0)
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
        f in _FIXED_SIZE_FUNCTIONS && !all(_is_fixed_size, values) && throw(_NotALiteral())
        # Exact powers grow with their arguments: bound them before computing (the result is checked as well).
        # (A division, not a product: the product of the exponent and the bits overflows for huge exponents.)
        if f === :^ && length(values) == 2
            bits = _exact_bits(values[1])
            bits > 0 && abs(values[2]) > _MAX_LITERAL_BITS / bits && throw(_NotALiteral())
        end
        result = _LITERAL_FUNCTIONS[f](values...)
        # Ranges are capped where they are built (they are only literals on their own, see `_literal_parts`).
        f === :(:) && return _checked_range(result, values)
        return _checked_number(result)
    end
    T = _literal_type(f, depth)
    if T <: Dict && all(v -> v isa Pair, values)
        # Building a dictionary compiles for its key and value types: bound them (also for untyped `Dict(…)`).
        all(p -> _type_size(typeof(p.first)) <= _MAX_TYPE_SIZE && _type_size(typeof(p.second)) <= _MAX_TYPE_SIZE,
            values) || throw(_NotALiteral())
        return T(values...)
    elseif T <: Val && isempty(values)
        return T()
    elseif T === Symbol && length(values) == 1 && values[1] isa AbstractString
        return Symbol(values[1])
    elseif T <: Number && length(values) == 1 && values[1] isa Number
        return _checked_number(T(values[1]))
    end
    throw(_NotALiteral())
end

"""
    str2val(val_str::AbstractString)

Inverse of [`val2str`](@ref): parses literals and returns anything else as a (cleaned) string. Arbitrary code is
never evaluated. Accepted are the values `val2str` writes: numbers, strings, symbols, characters, `nothing`,
`missing`, types, tuples, typed or untyped vectors, `reshape(T[...], dims)`, `Dict{K, V}(...)`, `Val{...}()` and
static arrays (`SA{T}[...]`); arithmetic on numbers such as `2π`, `1/3` or `sqrt(2)`; and a range as the whole
value (`1:10`, `0:0.1:1`).

Types come from an allowlist (the number types, including `Rational`, `Complex`, `Irrational` and the abstract ones,
text, `Tuple`/`NTuple`, `Vector`/`Matrix`/`Array`, `Dict`, `Pair`, `Val`, `Union`, `Type`, `DataType`, `UnionAll`,
`Function`, `Nothing`, `Missing`, `Any` and the static arrays of StaticArrays); other names stay strings. Values
beyond the size limits are returned as strings too: more than 10^6 elements in total, exact numbers with more than
2^20 bits (BigFloats: exponents), types of a size above 1024 (parameters, nested ones and static array elements
counted), more than 16 array dimensions, more than 32 levels of nesting, long operator chains, ranges of BigInts or
BigFloats with more than 2^24 bits in total, and functions such as `sin` or `sqrt` of a BigInt, BigFloat or
`Rational{BigInt}`.
"""
function str2val(val_str::AbstractString)
    s = strip(String(val_str))  # a plain String: the parser cannot iterate every AbstractString (e.g. lazy CSV strings)
    (s == "<empty>" || isempty(s)) && return ""
    try
        _too_nested(s) && throw(_NotALiteral())
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
