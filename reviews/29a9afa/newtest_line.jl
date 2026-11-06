# Evaluates one `@test` line (ARGS[1]) of test_str2val_differential.jl with the package of the active project
# (the scratch copy with 87c48e2's src, or the repo at 76c67a1); prints pass/fail and time.
using PDEStudioCore, StaticArrays, Test
ex = Meta.parse("@testset \"one\" begin\n" * ARGS[1] * "\nend")
t = @elapsed r = try
    ts = Core.eval(Main, ex)
    c = Test.get_test_counts(ts)
    (c.passes + c.cumulative_passes) > 0 && (c.fails + c.errors + c.cumulative_fails + c.cumulative_errors) == 0 ? "PASS" : "FAIL"
catch e
    "FAIL (" * first(sprint(showerror, e), 60) * ")"
end
println(rpad(first(ARGS[1], 90), 92), " ", r, "  (", round(t; digits = 2), " s)")
