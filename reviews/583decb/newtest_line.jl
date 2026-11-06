# Evaluates one test statement (ARGS[1]) of fbae679's new tests with the package of the active project
# (the review checkout at fbae679 or the worktree at 356e683); prints pass/fail and time.
using PDEStudioCore, StaticArrays, Test
pre = """T = PDEStudioCore._too_nested
lv(L, chain; sep = ", ") = foldl((inner, _) -> "(" * inner * chain * sep * "1)", 1:L; init = "1")
nestfirst(n, k) = foldl((inner, _) -> Any[inner, collect(1:k)...], 1:n; init = Any[1])
"""
ex = Meta.parse("@testset \"one\" begin\n" * pre * ARGS[1] * "\nend")
t = @elapsed r = try
    ts = Core.eval(Main, ex)
    c = Test.get_test_counts(ts)
    (c.passes + c.cumulative_passes) > 0 && (c.fails + c.errors + c.cumulative_fails + c.cumulative_errors) == 0 ? "PASS" : "FAIL"
catch e
    "FAIL (" * first(sprint(showerror, e), 60) * ")"
end
println(rpad(first(ARGS[1], 100), 102), " ", r, "  (", round(t; digits = 2), " s)")
