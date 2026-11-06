# After str2val hit a stack overflow in Meta.parse (4 KB text), does the process keep working?
using PDEStudioCore
s = "('\"', " * "["^2000 * "1" * "]"^2000 * ")"
println(typeof(str2val(s)))
println(str2val("Dict(:a => [1, 2])"), " ", calculate_hash(Dict(:a => 1)))
r = fetch(Threads.@spawn str2val(s)); println(typeof(r))
println(Meta.parse("1 + 2"), " ", str2val("SA[1.0, 2.0]"))
