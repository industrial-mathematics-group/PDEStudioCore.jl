# ==============================================================================
# --- Parameter serialisation, safe parsing & hashing ---
# ==============================================================================

# A top-level string whose unquoted text would read as further `key => value` pairs (pairs joined by `, `, keys are
# identifiers), e.g. `"x, b => 1"`, and `"<empty>"`, which would read as `""`: such strings are written quoted
# (`str2val` reads them back). Any other top-level text stays unquoted, since frontends write their own literal text
# through `val2str`, e.g. PDEStudio's typed CSV values such as `1.5f0`. (The hash doesn't depend on it, see `_identity`.)
_ambiguous_text(s::AbstractString) = s == "<empty>" || occursin(r", [A-Za-z_]\w* => ", s)

# The text of a type without module paths: types in parameters are identified by their name (`SVector{2, Float64}`,
# also where `StaticArraysCore.SVector` isn't visible in `Main`; `Wall` for `HyperCloud.Wall`; two types of one name are
# one value). `string(T)` qualifies the names `Main` doesn't see, so the text would depend on what the session loaded
# with `using`. The printed type is parsed by Julia's parser (nothing is evaluated) and the module paths are removed
# from the expression, so identifiers and quoted data (`Symbol("left.mode")`, characters) follow Julia's own syntax; a
# text without module paths is kept exactly as printed.
function _type_text(T)
    text = string(T)
    ex = try
        Meta.parse(text)
    catch
        return text
    end
    bare = _without_modules(ex)
    return bare == ex ? text : string(bare)
end
_without_modules(ex) =
    ex isa Expr && ex.head === :. && length(ex.args) == 2 && ex.args[2] isa QuoteNode && ex.args[2].value isa Symbol ?
        ex.args[2].value : ex isa Expr ? Expr(ex.head, map(_without_modules, ex.args)...) : ex

"""
    val2str(v; top_level::Bool = true)

Converts a value into a Julia-literal-like string (the basis of parameter normalisation).
Top-level strings are written unquoted (unless their text could be read as something else, see below),
strings inside containers are quoted, functions become
`"Closure"` (parameters refuse them), enum values are written as `TypeName.value` and custom structs as
`TypeName(field=value, ...)` from what identifies them ([`param_identity`](@ref); a struct with an empty identity as
its type with its parameters, e.g. `Limiter{:minmod}`).
Type names are written without module prefixes, so the text doesn't depend on what the session loaded with `using`.
"""
function val2str(v; top_level::Bool = true)
    if v isa AbstractString && isempty(v)
        return top_level ? "<empty>" : "\"\""   # (`<empty>` inside a container is no literal: the container would not read back)
    elseif isa(v, Function)
        return "Closure"
    elseif isa(v, Val)
        return _type_text(typeof(v)) * "()"
    elseif isa(v, Enum)
        # Enums have no fields, so the generic struct branch would reduce every value to the type name.
        return string(typeof(v).name.name, ".", Symbol(v))
    elseif isa(v, Symbol)
        return repr(v)
    elseif isa(v, AbstractString)
        return top_level && !_ambiguous_text(v) ? String(v) : repr(String(v))
    elseif isa(v, AbstractChar)
        return repr(v)
    elseif isa(v, Number)
        return string(v)
    elseif isa(v, Type)
        return _type_text(v)
    elseif isa(v, AbstractArray)
        T = eltype(v)
        prefix = T === Any ? "Any" : _type_text(T)
        elements = join([val2str(x; top_level = false) for x in v], ", ")
        # Multidimensional arrays keep their shape (vectors are written without `reshape`).
        return ndims(v) == 1 ? "$(prefix)[$elements]" : "reshape($(prefix)[$elements], $(val2str(size(v))))"
    elseif isa(v, Tuple)
        elements = join([val2str(x; top_level = false) for x in v], ", ")
        return length(v) == 1 ? "($elements,)" : "($elements)"
    elseif isa(v, Dict)
        K, V = keytype(v), valtype(v)
        # (keys in the order of `string`, as since hash format 4: parameters only hold Dicts with keys of one plain type,
        # Symbol, integer or String, whose distinct keys have distinct texts, so the order is canonical)
        sorted_keys = sort(collect(keys(v)), by = string)
        elements = join(["$(val2str(k; top_level = false)) => $(val2str(v[k]; top_level = false))" for k in sorted_keys], ", ")
        return "Dict{$(_type_text(K)), $(_type_text(V))}($elements)"
    else
        # a struct by what identifies it (`param_identity`; for other values, e.g. shown in a frontend, its fields)
        type_name = string(typeof(v).name.name)
        fields = _declares_identity(v) ? pairs(_identity_of(v)) : (f => getproperty(v, f) for f in propertynames(v))
        isempty(fields) && return _type_text(typeof(v))   # (a tag such as `Limiter{:minmod}()`: its parameters tell it apart)
        field_strs = ["$f=$(val2str(x; top_level = false))" for (f, x) in fields]
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
const _MAX_TERMS = 1024            # tokens in a chain of the text (see `_too_nested`)

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
# static array types with a free element type (`SArray{Tuple{1000, 1000}}`), and the length parameter `L` of
# `SArray`/`MArray` (it sets their layout). Returns at most `limit + 1`.
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
    if T.name.wrapper <: StaticArray && !isempty(T.parameters)
        # the elements: of the size (`Tuple{2, 3}`), and for `SArray`/`MArray` of the length parameter `L`, which sets
        # the layout (`NTuple{L, T}`) even where it disagrees with the size
        n = 0
        S = T.parameters[1]
        if S isa DataType && S <: Tuple && all(d -> d isa Integer, S.parameters)
            n = 1
            for d in S.parameters
                n *= max(d, 0)
                n > limit && return limit + 1
            end
        end
        L = T.name.wrapper in (SArray, MArray) && length(T.parameters) >= 4 ? T.parameters[4] : nothing
        L isa Integer && (n = max(n, L))
        n > limit && return limit + 1
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

# Whether the text nests too deep for `Meta.parse` (which can overflow the stack on deep nesting), judged from the
# tokens of Julia's own (iterative) lexer, so Char and string literals, interpolation and comments are read exactly:
# - brackets nested more than `_MAX_DEPTH` levels;
# - more than `_MAX_TERMS` tokens in a chain along the open brackets: the tokens since the last separator (`,`, `;`)
#   of each open level, where a closed group counts with its longest element (`1-1-1…`, `- - -1`, `1''…`,
#   `(1)^(1)^…`, `((1)'…, 1)'…`, also spread over levels);
# - macro calls (`@a 1, @a 1, …`), keywords (`begin`, `return`, …) and assignment operators (`x = 1, x = 1, …`, `~`,
#   `:=`), which nest through commas or `;`. Keywords and assignment operators are let through right after a quoting
#   `:` (one in prefix position: at the start, after an opening bracket, a separator or `=>`; no whitespace between
#   the `:` and the token), as in the Symbols `:begin` and `:~`, the one form in which `val2str` writes them in
#   literals; also right after `:(` (`:(=)`; a quoted expression there costs a bracket level) and assignment
#   operators after `:.` (`:.=`).
# `val2str` writes elements separated by commas, each of a few tokens.
# (`Base.JuliaSyntax.Tokenize` is internal to Julia; it is used as in Julia 1.12 and 1.13.)
const _JS = Base.JuliaSyntax
_quote_position(k) = k in (_JS.K"Whitespace", _JS.K"(", _JS.K"[", _JS.K"{", _JS.K",", _JS.K";", _JS.K"=>")
function _too_nested(s::AbstractString)
    # tokens since the last separator of the current level, its longest element so far, the same of each enclosing
    # level, and the sum of their current chains
    terms, longest, outer, open = 0, 0, Tuple{Int, Int}[], 0
    # the last three tokens (`K"Whitespace"`: the start of the text), and whether whitespace followed the last two
    p1, p2, p3 = _JS.K"Whitespace", _JS.K"Whitespace", _JS.K"Whitespace"
    space1, space2 = false, false
    for token in _JS.Tokenize.tokenize(s)   # (the lexer only: `_JS.tokenize` parses too)
        k = _JS.kind(token)
        if _JS.is_whitespace(k) || k == _JS.K"Comment"
            space1 = true
            continue
        end
        k == _JS.K"EndMarker" && continue
        # right after a quoting `:` (`:begin`), or after `:(` or `:.` (`:(=)`, `:.=`)
        quoted = (p1 == _JS.K":" && !space1 && _quote_position(p2)) ||
                 ((p1 == _JS.K"(" || (p1 == _JS.K"." && _JS.is_prec_assignment(k))) && p2 == _JS.K":" && !space1 &&
                  !space2 && _quote_position(p3))
        if k in (_JS.K"(", _JS.K"[", _JS.K"{")
            push!(outer, (terms, longest))
            open += terms
            length(outer) > _MAX_DEPTH && return true
            terms = longest = 0
        elseif k in (_JS.K")", _JS.K"]", _JS.K"}")
            # a closed group continues the chain of its level with its longest element (an unmatched closer
            # starts over: the parser stops there)
            if isempty(outer)
                terms = longest = 0
            else
                inner = max(longest, terms, 1)
                enclosing, longest = pop!(outer)
                open -= enclosing
                terms = enclosing + inner
            end
        elseif k in (_JS.K",", _JS.K";")
            longest = max(longest, terms)
            terms = 0
        elseif k == _JS.K"@" || (((_JS.is_keyword(k) && k != _JS.K"var") || _JS.is_prec_assignment(k)) && !quoted)
            return true
        else
            terms += 1
        end
        open + terms > _MAX_TERMS && return true
        p3, p2, p1 = p2, p1, k
        space2, space1 = space1, false
    end
    return false
end

# `base^exponent` of integers as a literal means it: a negative exponent gives a float (`10^-6 == 1.0e-6`, like
# Julia's `literal_pow`; the runtime `^` throws a DomainError), and a result the base's type cannot hold is refused
# instead of wrapping around (`10^19` is not `-8446744073709551616`).
function _integer_power(base::Integer, exponent::Integer)
    exponent < 0 && return float(base)^exponent
    (base isa BigInt || base isa Bool) && return base^exponent
    result = big(base)^exponent
    typemin(typeof(base)) <= result <= typemax(typeof(base)) || throw(_NotALiteral())
    return typeof(base)(result)
end

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
        result = f === :^ && length(values) == 2 && values[1] isa Integer && values[2] isa Integer ?
                 _integer_power(values[1], values[2]) : _LITERAL_FUNCTIONS[f](values...)
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
counted), more than 16 array dimensions, more than 32 levels of nesting, more than 1024 tokens between separators
(`,`, `;`) along the open brackets, keywords (`begin`, `if`, …) and assignments outside of Symbols such as `:begin`
or `:~`, macro calls, ranges of BigInts or BigFloats with more than 2^24 bits in total, and functions such as `sin`
or `sqrt` of a BigInt, BigFloat or `Rational{BigInt}`.
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
# re-interpreted as code), other values round-trip through val2str. Only data identifies a run: functions, and values
# of custom types that don't declare their identity (`param_identity`), are refused (`_check_param`).
# `nothing`/`missing` are parameter values only on their own: inside containers they would come back as the types
# `Nothing`/`Missing`, so they are refused there (`_check_param`), and the types are the only nested form.
_normalize_param(v::AbstractString) = String(v)
_normalize_param(v::Union{Nothing, Missing}) = v  # would otherwise become the types `Nothing`/`Missing`
_normalize_param(v) = str2val(val2str(v))
function _normalize_params(params)
    foreach(((k, v),) -> _check_param(v, ":$k"; top = true), params)
    return ParamDict(Symbol(k) => _normalize_param(v) for (k, v) in params)
end

# --- What may be a parameter value ----------------------------------------------------------------------------------
"""
    param_identity(x) -> NamedTuple

What identifies a value of a custom type when it is part of a run's parameters: a `NamedTuple` (plain identifiers as names) of data (numbers,
strings, symbols, tuples, arrays, dictionaries, types, and values of types that declare their own identity). Only
this is stored and hashed; the other fields of the value are never looked at. Define it for every type whose values
appear in parameters; a value of a type without it is refused (as are functions), so nothing that can't be compared
reliably (functions, caches, derived fields) decides which run is which. For types whose fields are all data,
[`@param_struct`](@ref) declares all fields at once.

```julia
# without its functions (is_interior, get_tag) and derived fields (volume)
PDEStudioCore.param_identity(d::GeometricDomain) =
    (; label = d.label, mins = d.mins, maxs = d.maxs, is_periodic = d.is_periodic, bc_map = d.bc_map, shape = d.shape)
```

It is stored as `TypeName(key=value, …)`; see "What identifies a parameter value" in the manual.
"""
function param_identity end

"""
    @param_struct T
    @param_struct struct T … end

Declares that every stored field of the struct `T` is part of what identifies its values in parameters (its
[`param_identity`](@ref) is the `NamedTuple` of all fields): for types whose fields are all data, such as boundary
conditions or shapes. Written in front of a struct definition, it defines the struct, too.

```julia
@param_struct struct Wall <: AbstractBC
    id::Int
end
@param_struct Limiter   # an existing type (here a tag without fields: identified by its type parameters)
```
"""
macro param_struct(ex)
    name = ex isa Expr && ex.head === :struct ? _struct_name(ex.args[2]) : ex
    definition = :($(@__MODULE__).param_identity(x::$(esc(name))) = $(@__MODULE__)._all_fields(x))
    return ex isa Expr && ex.head === :struct ? Expr(:block, esc(ex), definition, nothing) : Expr(:block, definition, nothing)
end
_struct_name(e) = e isa Symbol ? e : e.head === :(<:) ? _struct_name(e.args[1]) : e.head === :curly ? e.args[1] :
                  throw(ArgumentError("@param_struct: can't read the struct name from $e"))
_all_fields(x) = NamedTuple{fieldnames(typeof(x))}(map(f -> getfield(x, f), fieldnames(typeof(x))))   # (stored fields, not properties)

# (in the latest world, as `_identity_of` calls it: a declaration included later, e.g. from `config.sources`, counts)
_declares_identity(v) = hasmethod(param_identity, Tuple{typeof(v)}; world = Base.get_world_counter())
function _identity_of(v)
    id = Base.invokelatest(param_identity, v)   # (declared after the caller started, e.g. in a script)
    id isa NamedTuple || throw(ArgumentError("param_identity(::$(typeof(v))) must return a NamedTuple, got $(typeof(id))"))
    for k in keys(id)   # (the stored form is `TypeName(key=value, …)`: other names could forge another identity's text)
        Base.isidentifier(k) || throw(ArgumentError("param_identity(::$(typeof(v))) returned the field name $(repr(k)), " *
                                                    "which isn't a plain Julia identifier"))
    end
    return id
end

# The numbers of parameters: explicit types, each written in one way (`Float32`/`Float16` are stored as `Float64`, by
# design). Other numbers (other integer widths, BigInt, rationals, complex, user-defined Number types) would be read
# back as another type or print two values alike: convert them for the parameters (e.g. `Int64(x)`)
const _NUMBERS = Union{Bool, Int64, Float64, Float32, Float16}
# Values that are data as they are, and element types whose arrays need no look at every element (other strings,
# types, `Val`s and enum values are checked one by one, below; named tuples are refused)
const _PLAIN = Union{String, SubString{String}, Symbol, Char, _NUMBERS, Nothing, Missing}
# The values a type written in parameters may have as type parameters (`Val{1}`, `Limiter{:minmod}`, `SVector{3, Float64}`):
# explicit types whose distinct values print distinct texts (`Int32(1)` prints as `1`, a type parameter is written as text)
const _TYPE_PARAMETERS = Union{Symbol, Char, Bool, Int64, Float64, Float32, Float16, Nothing}
# The key types of a Dict in parameters: explicit types whose distinct values have distinct texts, so the order by
# text is canonical
const _KEY_TYPES = Union{Symbol, String, Int64}

# Parameters read from a file, normalised, or `nothing` if they aren't valid parameters of this version (e.g. a Dict
# with keys of another type, written by an earlier one): such a file isn't part of the store, and scans go on without it
function _valid_stored(p)
    p isa AbstractDict || return nothing
    try
        return _normalize_params(p)
    catch e
        e isa ArgumentError || rethrow()
        return nothing
    end
end
# (`nothing`/`missing` elements are refused, below: their arrays are looked at element by element)
_plain_eltype(T) = (T <: _PLAIN && !(Nothing <: T) && !(Missing <: T)) || (T <: StaticArray && eltype(T) <: _NUMBERS)

# Refuses a type (written as text: its name and parameters) whose parameters include a value that doesn't print as
# itself (e.g. `Val{Int32(1)}`, written like `Val{1}`, or a value of a custom type)
function _check_type(T, path::AbstractString)
    if T isa Union
        _check_type(T.a, path); _check_type(T.b, path)
    elseif T isa UnionAll
        _check_type(T.var, path); _check_type(T.body, path)
    elseif T isa TypeVar
        _check_type(T.lb, path); _check_type(T.ub, path)
    elseif T isa Core.TypeofVararg
        isdefined(T, :T) && _check_type(T.T, path)
        isdefined(T, :N) && _check_type_parameter(T.N, T, path)
    elseif T isa DataType
        foreach(p -> _check_type_parameter(p, T, path), T.parameters)
    end
    return nothing
end
function _check_type_parameter(p, T, path::AbstractString)
    if p isa Union{Type, TypeVar, Core.TypeofVararg}
        _check_type(p, path)
    elseif p isa Tuple
        foreach(x -> _check_type_parameter(x, T, path), p)
    elseif p isa AbstractFloat && isnan(p)
        throw(ArgumentError(
            "the parameter $path has the type $(_type_text(T)) with NaN as a type parameter: NaNs with other bits are " *
            "other types but are all written `NaN`; use another value (e.g. a Symbol) to tell such types apart"))
    elseif !(p isa _TYPE_PARAMETERS)
        throw(ArgumentError(
            "the parameter $path has the type $(_type_text(T)) with the type parameter $(repr(p)) of type $(typeof(p)): " *
            "types in parameters are written as text, so their parameters are Symbols, Chars, Int64, Bool, floats or " *
            "`nothing` (e.g. `Val{1}`, not `Val{Int32(1)}`)"))
    end
    return nothing
end

# Refuses what can't identify a run: functions, values of custom types that don't declare their identity
# (`param_identity`), and `nothing`/`missing` below the top level (`top = false`: inside a container or an identity they are
# written as the types `Nothing`/`Missing`, which are values as well); `path` names the place in the parameters for the message
function _check_param(v, path::AbstractString; top::Bool = false)
    (v === nothing || v === missing) && !top && throw(ArgumentError(
        "the parameter $path is `$v` inside a container or an identity, where it would be stored as the type " *
        "`$(typeof(v))` (and be the same value as that type): leave the entry out, or use a Symbol (e.g. `:none`) or " *
        "the type `$(typeof(v))` itself; `$v` is a parameter value only on its own"))
    v isa Function && throw(ArgumentError(
        "the parameter $path is a function ($v): what a function computes can't be compared, so a function can't tell " *
        "runs apart. Give it a name instead (e.g. a String or Symbol the solver looks up), or wrap it in a struct whose " *
        "`param_identity` names it."))
    v isa _PLAIN && return nothing
    v isa AbstractChar && throw(ArgumentError(
        "the parameter $path is a character of type $(typeof(v)): characters in parameters are `Char`s; convert it " *
        "(`Char(c)`), or use a type of your own that isn't a character and declares `param_identity`"))
    if v isa Union{AbstractString, Enum}   # (a string by its text, an enum value by its type's name and its name)
        _declares_identity(v) && throw(ArgumentError(
            "the parameter $path has the type $(typeof(v).name.name), which declares `param_identity` but is " *
            (v isa Enum ? "an enum" : "a string") * ": it is stored by its " * (v isa Enum ? "name" : "text") *
            ", not by its identity; use a type of your own that isn't a string or an enum"))
        return nothing
    end
    v isa Type && return _check_type(v, path)
    v isa Val && return _check_type(typeof(v), path)
    v isa Number && throw(ArgumentError(
        "the parameter $path has the type $(typeof(v)): numbers in parameters are Int64, Float64 (Float32 and Float16 are stored " *
        "as Float64) or Bool; convert it for the parameters (e.g. Int64(x)), also if the solver uses another type"))
    v isa AbstractSet && throw(ArgumentError(
        "the parameter $path is a set: its order would depend on how it was built; use a sorted Vector or a Tuple"))
    if v isa Union{AbstractArray, Tuple}
        v isa AbstractArray && _check_type(eltype(v), path)   # (written with the array)
        _plain_eltype(eltype(v)) && return nothing
        for (i, x) in enumerate(v)
            _check_param(x, "$path[$i]")
        end
    elseif v isa Dict
        K = keytype(v)
        (isconcretetype(K) && K <: _KEY_TYPES) || throw(ArgumentError(
            "the parameter $path is a Dict with keys of type $K: the keys of a Dict in parameters are Symbols (a " *
            "ParamDict), Strings or Int64, all of one type"))
        _check_type(valtype(v), path)
        for (k, x) in v
            _check_param(x, "$path[$(repr(k))]")
        end
    elseif v isa NamedTuple   # (a struct of its own: its names would be data, and a declared identity is one already)
        throw(ArgumentError(
            "the parameter $path is a named tuple: use a Dict, or for the identity of a custom type its own fields " *
            "(the NamedTuple that `param_identity` returns, not one inside it)"))
    elseif v isa Pair
        foreach(f -> _check_param(getfield(v, f), "$path.$f"), fieldnames(typeof(v)))
    elseif _declares_identity(v)
        id = _identity_of(v)
        isempty(id) && _check_type(typeof(v), path)   # (an empty identity: written as the type with its parameters)
        for (k, x) in pairs(id)
            _check_param(x, "$path.$k")
        end
    else
        throw(ArgumentError(
            "the parameter $path has the type $(typeof(v).name.name), which doesn't declare what identifies it. Define " *
            "`PDEStudioCore.param_identity(x::$(typeof(v).name.name))` returning a NamedTuple of the data that tells such " *
            "values apart (leave out functions and derived fields), or write `@param_struct $(typeof(v).name.name)` if all " *
            "its fields are data."))
    end
    return nothing
end

"""
    calculate_hash(params::AbstractDict)

SHA-256 hash (hex string) of the normalised parameters ([`get_clean_params`](@ref)), the name of their data file
(`<save path>/data/<hash>.jld2`). It digests a canonical encoding of the parameters: a header naming the hash format,
then every value tagged with its kind (string, symbol, number with its type, container with its type and size, …) and
every text prefixed by its length, keys sorted. Distinct normalised parameters therefore have distinct encodings
(`true` and `1`, `"1"` and `1`, `nothing` and `Nothing`, `[1 2]` and `[1, 2]` differ) and, up to SHA-256 collisions,
distinct hashes. Hash format 4 (PDEStudioCore 0.8); data of earlier versions is brought in with
[`import_sim_data`](@ref).
"""
function calculate_hash(params::AbstractDict)
    clean = _normalize_params(params)   # (as stored: a struct stored as its text hashes like that text)
    return bytes2hex(sha256(_identity(clean)))
end

# The canonical encoding of normalised parameters (what the hash digests). Stored parameters are compared by it, not
# by `isequal` (which takes `true` for `1`), so a file is only ever taken for the parameters its name stands for.
function _identity(clean::AbstractDict)
    io = IOBuffer()
    print(io, "PDEStudioCore hash format ", _HASH_FORMAT, "\n")
    _encode(io, clean)
    return String(take!(io))
end

# A tag (one character) for the kind of a value, then its content: texts with their length (`<n>:<text>`), containers
# with their type, size and encoded elements. Every encoding reads back in one way only (the tag says what follows,
# lengths and counts say where it ends), so distinct values never share one.
_encode_text(io::IO, s::AbstractString) = (s = String(s); print(io, ncodeunits(s), ":", s); nothing)
_encode(io::IO, ::Nothing) = (print(io, "n"); nothing)
_encode(io::IO, ::Missing) = (print(io, "m"); nothing)
_encode(io::IO, v::Bool) = (print(io, v ? "b1" : "b0"); nothing)
_encode(io::IO, v::AbstractString) = (print(io, "s"); _encode_text(io, v))
_encode(io::IO, v::Symbol) = (print(io, "y"); _encode_text(io, String(v)))
_encode(io::IO, v::AbstractChar) = (print(io, "c"); _encode_text(io, repr(v)))
_encode(io::IO, v::Number) = (print(io, "#"); _encode_text(io, _type_text(typeof(v))); _encode_text(io, string(v)))
_encode(io::IO, v::Type) = (print(io, "t"); _encode_text(io, _type_text(v)))
_encode(io::IO, v::Pair) = (print(io, "p"); _encode(io, v.first); _encode(io, v.second))
function _encode(io::IO, v::Tuple)
    print(io, "(", length(v), ":")
    foreach(x -> _encode(io, x), v)
    return nothing
end
function _encode(io::IO, v::AbstractArray)
    print(io, "a")
    _encode_text(io, string(nameof(typeof(v))))   # (Array, SArray, UnitRange, …)
    _encode_text(io, _type_text(eltype(v)))
    print(io, ndims(v), ":", join(size(v), ","), ":")
    foreach(x -> _encode(io, x), v)
    return nothing
end
function _encode(io::IO, v::AbstractDict)
    entries = [(sprint(_encode, k), sprint(_encode, x)) for (k, x) in v]
    print(io, "d")
    _encode_text(io, _type_text(typeof(v)))
    print(io, length(entries), ":")
    for (k, x) in sort!(entries, by = first)   # (sorted by the encoded key: one order for every dictionary)
        print(io, k, x)
    end
    return nothing
end
# anything else (e.g. `Val`s): its type and `val2str` text
_encode(io::IO, v) = (print(io, "x"); _encode_text(io, _type_text(typeof(v))); _encode_text(io, val2str(v)))

# The canonical encoding of parameters as they are stored in a file (not normalised again), or `nothing`
_raw_identity(stored) = stored isa AbstractDict ? _identity(ParamDict(Symbol(k) => v for (k, v) in stored)) : nothing

# Whether two normalised values are the same parameter value: the same canonical encoding (`1`, `1.0` and `true`
# differ, unlike for `isequal`)
_same_value(a, b) = sprint(_encode, a) == sprint(_encode, b)

# Whether normalised parameters contain all `pairs` (keys strings or symbols; values normalised here), compared as values
# of the hash (`_same_value`)
function _has_pairs(clean::AbstractDict, pairs)
    pairs = collect(pairs)   # (read once: a one-pass iterator would be used up by the check)
    foreach(((k, v),) -> _check_param(v, ":$k"), pairs)   # (a filter value is a parameter value: a function is refused)
    return all(((k, v),) -> haskey(clean, Symbol(k)) && _same_value(clean[Symbol(k)], _normalize_param(v)), pairs)
end

# The hash format of `calculate_hash` (see there): 4 since PDEStudioCore 0.8 (3: 0.7, 2 was never released)
const _HASH_FORMAT = 4

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
