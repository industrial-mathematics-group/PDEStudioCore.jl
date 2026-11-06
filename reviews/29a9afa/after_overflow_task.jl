# A scanner bypass (interpolation, 4 KB) parsed inside a task, then the process keeps working
using PDEStudioCore
s = "\"\$(" * "["^2000 * "1" * "]"^2000 * ")\""
r = fetch(Threads.@spawn str2val(s))
println("task result: ", typeof(r))
println("after: ", str2val("Dict(:a => [1, 2])"), "  hash ", calculate_hash(Dict(:x => 1))[1:12])
