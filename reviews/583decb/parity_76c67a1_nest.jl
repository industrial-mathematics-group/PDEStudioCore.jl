# For values val2str can write (and a few hand-typed texts): typeof(str2val(text)) and whether the hash text changes,
# with the package of the active project (run once at 76c67a1, once with 87c48e2's src) and the reference parser.
using PDEStudioCore, StaticArrays
include(ARGS[1])  # test/reference_str2val.jl
nest(f, n) = (v = 1; for _ in 1:n; v = f(v); end; v)
values = Any[
    Any['"', "("^40], ('"', "-"^1100), ('"', "x", "["^33), fill('(', 33), fill('(', 32), ['"', '"'], '"',
    nest(v -> [v], 31), nest(v -> [v], 32), nest(v -> [v], 33), nest(v -> (v,), 33), nest(v -> Dict(:a => v), 16),
    nest(v -> Dict(:a => v), 17), ["\"", "("^40], ["a\\", "(" ^ 40], Symbol("("^40), [Symbol("\"")], "-"^2000,
    [1//2 + 3//4 * im], Complex{Rational{BigInt}}(big(2)^70 // 3, 1), reshape(fill(-1.5e-5, 1200), 2, 600),
    nest(v -> SA[v], 33), NTuple{4, NTuple{4, Float64}}, nest(T -> Vector{T}, 33), nest(T -> Vector{T}, 32),
]
typed = ["\"\"\"a\"" * "("^40 * "\"\"\"", "'\"'", "('\"', 1)", "\"a#b\"", "1 # \"\n", "1 #= ((( =#"]
for (i, v) in enumerate(values)
    s = val2str(v)
    new, old = str2val(s), OldStr2Val.str2val(s)
    println(rpad(i, 4), rpad(first(s, 50), 52), " new: ", rpad(first(string(typeof(new)), 30), 32), " old: ",
            rpad(first(string(typeof(old)), 30), 32), " hash text equal: ", val2str(new) == val2str(old))
end
for s in typed
    new, old = str2val(s), OldStr2Val.str2val(s)
    println("    ", rpad(repr(first(s, 48)), 52), " new: ", rpad(first(repr(new), 30), 32), " old: ", first(repr(old), 30))
end
