# Evaluates one line (ARGS[1]) of the new tests of test_str2val_differential.jl (356e683) with the package of the
# active project (the review checkout or the worktree at a1f8627); prints pass/fail and time.
using PDEStudioCore, StaticArrays, Test
pre = "T = PDEStudioCore._too_nested\nlevels(L, head, tail = \"\") = foldl((inner, _) -> \"(\" * head * inner * tail * \")\", 1:L; init = \"1\")\n"
ex = Meta.parse("@testset \"one\" begin\n" * pre * ARGS[1] * "\nend")
t = @elapsed r = try
    ts = Core.eval(Main, ex)
    c = Test.get_test_counts(ts)
    (c.passes + c.cumulative_passes) > 0 && (c.fails + c.errors + c.cumulative_fails + c.cumulative_errors) == 0 ? "PASS" : "FAIL"
catch e
    "FAIL (" * first(sprint(showerror, e), 60) * ")"
end
println(rpad(first(ARGS[1], 90), 92), " ", r, "  (", round(t; digits = 2), " s)")
