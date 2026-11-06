# Static arrays with more than about 1000 elements, as val2str writes them: parsed (type) or String, per parser.
using PDEStudioCore, StaticArrays
include(ARGS[1]); const Old = OldStr2Val
vals = Any[[@SMatrix zeros(32, 32)], [SVector{1019}(zeros(1019))], SMatrix{32, 32, Float64, 1024}, [@SMatrix zeros(31, 32)], Dict(:S => SMatrix{32, 32, Float64, 1024})]
for v in vals
    s = val2str(v); a, b = str2val(s), Old.str2val(s)
    println(rpad(first(s, 45), 47), " this: ", rpad(first(string(typeof(a)), 34), 36), " reference: ", first(string(typeof(b)), 34), "  hash text equal: ", val2str(a) == val2str(b))
end
