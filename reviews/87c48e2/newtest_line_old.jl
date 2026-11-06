# Evaluates one `@test` expression (ARGS[1]) with the previous parser in place of str2val; prints pass/fail.
using PDEStudioCore, StaticArrays, Test
include(joinpath(@__DIR__, "../repo/test/reference_str2val.jl"))
const str2val = OldStr2Val.str2val
ex = Meta.parse(ARGS[1])
t = @elapsed r = try Core.eval(Main, ex) catch e; "error: " * first(sprint(showerror, e), 80) end
println(rpad(first(ARGS[1], 70), 72), " old: ", r, "  (", round(t; digits = 2), " s)")
