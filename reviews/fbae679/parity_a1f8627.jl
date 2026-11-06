# Values val2str writes that touch the new scanner (Chars, words, unicode, operators, strings with quotes/brackets),
# at 29a9afa against the reference parser: type of the result and whether the hash text changes.
using PDEStudioCore, StaticArrays
include(ARGS[1])  # test/reference_str2val.jl
same(a, b) = a === b || (isequal(a, b) && typeof(a) == typeof(b))
struct PStruct; a::Any; b::Any; end
@enum PColor PRed PBlue
values = Any[
    '\'', '\\', 'é', '\U10ffff', '"', '#', '$', Char(0x110000), reinterpret(Char, 0xf8000000), reinterpret(Char, 0xc0800000),
    Any['\'', '\\', 'é', "a'b"], ('\'', '"'), Char['\'', '"', '\''], Dict('\'' => '"'), Dict('"' => '\''), ['\'', '\''],
    ("a'b", '\''), ("'", "\""), ["\"(((", "'"], ['\'', '"', "[[[["],
    ("\$x", "#c"), "a"^5000, ["\$(1+1)"], Any["\"\"\"", "("^40],
    1e5, 1.5f0, 0x1f, 2π, 1im, 2.5 - 1im, 1//3, -7//4 + 2//3 * im, big"1.5"^100, big(2)^300, Int128(2)^100, Float16(1.5),
    NaN32, -Inf16, BigFloat("1e-400"), Complex{BigFloat}(1, 2), Complex{Rational{BigInt}}(big(2)^70 // 3, 1),
    [Symbol("k", i) for i in 1:5000], Tuple(Symbol("k", i) for i in 1:3000), Dict(Symbol("k", i) => -i for i in 1:3000),
    [:α, :β₁, :x′, :ẋ, :∇u, :Δt, :u!, :_x, :x_1, :ħ], Symbol("α₁"^20), Symbol("x̂"^20), [Symbol("x", "₁"^600)],
    Symbol("x" * "′"^1100), :+, :(=>), Symbol("a.b"), Symbol("1x"), Symbol("end"), Symbol("begin"),
    reshape(collect(-1.5:-1:-12.5), 3, 4), reshape([1//2 + 1im for _ in 1:6], 2, 3), reshape(BigFloat[1, 2], 1, 2),
    SVector(1.0, -2.0), SMatrix{2, 2}(1, 2, 3, 4), MMatrix{2, 3}(1.0:6.0...), SA[SA[1, 2], SA[3, 4]], SArray{Tuple{2, 2, 2}}(1:8...),
    SVector{3, Complex{Float64}}(1im, 2, 3), Dict(SA[1, 2] => SA[1.0, 2.0]), Dict{Symbol, Any}(:a => SA[1.0], :b => "x'y"),
    SVector{64, Float64}, SArray{Tuple{2, 2}, Int, 2, 4}, MArray{Tuple{3}, Float64, 1, 3}, SVector{3}, SMatrix{2, 2},
    PStruct(1, '\''), PStruct("a\"b", [1, 2]), PRed, Val(:x), Val('\''),
    Dict(:f => sin, :g => (x -> x)), typeof(x -> x), Vector{typeof(sin)}, [x -> x],
    (a = 1, b = '\''), (; x = [1.0, 2.0]), Pair(:a, '\''), :a => (1, 2), Any[1 => 2, 3 => 4],
    Union{Int, Nothing}, Tuple{Vararg{Int}}, NTuple{3, SVector{2, Float64}}, Type{Int}, Array{Float64, 3},
    1:10, 0:0.5:2, range(0, 1; length = 5), "1:10", ["x" => 1],
    # added in this round: keyword-adjacent and lexer-sensitive values
    [:type, :as, :outer, :doc, :public, :abstract, :mutable, :primitive, :var, :end, :begin, :if, :do, :where, :in, :isa],
    Dict(:end => 1, :type => 2), Val(:begin), Val{:end}, (:as, :outer), Symbol("var"), Symbol("a b"), Symbol("end x"),
    Symbol("#a"), [true, false], Val(true), Any[nothing, missing], "begin end", ["begin", "if x end"], ["\$(begin)"],
    ["#= x =#", "# c"], ["\"\"\"", "`cmd`"], [Symbol("x" * "′"^1100)], [Symbol("x", "!"^1100)], Symbol("x" * "\u0302"^1100),
    Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[1]]]]]]]]]], [collect(1:2000)], Dict(i => -i for i in 1:3000),
    fill(1 // 3, 1000), fill(1.0 - 2.0im, 1000), fill(-big(2)^200, 200), (1, (2, (3, (4, (5, (6, (7, (8, 9)))))))),
    PStruct(:type, :end), PColor, Tuple{Symbol, Val{:end}}, Vector{Union{Int, Missing}},
]
nd = 0; nh = 0
for (i, v) in enumerate(values)
    s = val2str(v)
    new = try str2val(s) catch e; "ERROR $(typeof(e))" end
    old = try OldStr2Val.str2val(s) catch e; "ERROR $(typeof(e))" end
    d = !same(new, old); h = val2str(new) == val2str(old)
    global nd += d; global nh += !h
    println(rpad(i, 4), rpad(first(s, 44), 46), " new: ", rpad(first(string(typeof(new)), 28), 30), " old: ",
            rpad(first(string(typeof(old)), 28), 30), d ? " DIFF" : "     ", " hash text equal: ", h,
            " roundtrip: ", same(new, v))
end
println("values: ", length(values), ", parse differences: ", nd, ", hash-text differences: ", nh)
