# Evaluates one line (ARGS[1]) of the new tests of test_str2val_differential.jl with the package of the active
# project (the review checkout at a1f8627 or the worktree at 29a9afa); prints pass/fail and time.
using PDEStudioCore, StaticArrays, Test
ex = Meta.parse("@testset \"one\" begin\nT = PDEStudioCore._too_nested\ndeep = \"[\"^2000 * \"1\" * \"]\"^2000\n" * ARGS[1] * "\nend")
t = @elapsed r = try
    ts = Core.eval(Main, ex)
    c = Test.get_test_counts(ts)
    (c.passes + c.cumulative_passes) > 0 && (c.fails + c.errors + c.cumulative_fails + c.cumulative_errors) == 0 ? "PASS" : "FAIL"
catch e
    "FAIL (" * first(sprint(showerror, e), 60) * ")"
end
println(rpad(first(ARGS[1], 90), 92), " ", r, "  (", round(t; digits = 2), " s)")
