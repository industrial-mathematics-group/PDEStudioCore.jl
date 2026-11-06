# val2str values that touch the changes of 356e683 (`@`, assignment-precedence tokens, path-wide budget, carry),
# against the reference parser: result types and whether the hash text changes.
using PDEStudioCore, StaticArrays
include(ARGS[1])  # test/reference_str2val.jl
same(a, b) = a === b || (isequal(a, b) && typeof(a) == typeof(b))
struct PStruct; a::Any; b::Any; end
ops = Symbol.(["~", "=", "+=", "-=", "*=", "/=", "//=", "^=", "÷=", "%=", "|=", "&=", "⊻=", "<<=", ">>=", ">>>=", ":=", ".=",
               ".+=", ".~", "≔", "⩴", "≕", "\$=", "=>", "->", "-->", "&&", "||", "?", "@", "@a", "@time", "...", "::", "<:", "begin"])
nest(n, k) = foldl((inner, _) -> Any[collect(1:k)..., inner], 1:n; init = Any[1])
nestlast(n, k) = foldl((inner, _) -> Any[inner, collect(1:k)...], 1:n; init = Any[1])
nestdict(n) = foldl((inner, i) -> Dict{Symbol, Any}(Symbol("k", i) => inner, :x => collect(1.0:200.0)), 1:n; init = 1)
values = Any[
    ops..., [ops...], Tuple(ops), Dict(o => 1 for o in ops), Dict(1 => o for o in ops),
    Val(:~), Val(Symbol("=")), Val(Symbol(":=")), Val{:~}, Val{Symbol("=")}, Tuple{Val{:~}, Int}, (:~, 1), Any[:~ => 1],
    nest(30, 100), nestlast(30, 100), nest(31, 3), nestdict(15), nestdict(30),
    Dict{Symbol, Any}(:a => Any[Any[Any[collect(1:3000)]]], :b => (1, (2, (3, (4, fill(1 // 3, 2000)))))),
    Tuple(fill(1.0 - 2.0im, 2000)), Dict(Symbol("k", i) => (i, -i, 1 // i) for i in 1:2000),
    [Dict(:a => [1, 2], :b => (3, 4)) for _ in 1:500], fill(SA[1.0, 2.0], 1000), reshape(fill(1 // 3, 2000), 40, 50),
    Any[Any[1 => 2 => 3 => 4 => 5]], Any[(:a, :b) => (:c => :d)], (:begin, :end, :~), PStruct(:~, 1),
    NamedTuple{(:a,), Tuple{Int}}, (a = 1,), Pair(1, 2), Pair(:~, Symbol(":=")), :a => :b, Dict(:p => (1 => 2)),
    Any[fill(-1.5e-300, 1000)...], [big(2)^1000 // 3 for _ in 1:50], Complex{Rational{BigInt}}(big(2)^70 // 3, -1),
    fill(Float16(-1.5), 3000), [Symbol("a", "!"^500) for _ in 1:3], Symbol("x" * "'"^10), Symbol("x" * "′"^5000),
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
            " T: ", PDEStudioCore._too_nested(s))
end
println("values: ", length(values), ", parse differences: ", nd, ", hash-text differences: ", nh)
