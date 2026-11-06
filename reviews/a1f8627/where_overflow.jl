# Where the overflow happens: Meta.parse alone on the literal ARGS[1], outside str2val
using PDEStudioCore
s = read(ARGS[1], String)
println("_too_nested = ", PDEStudioCore._too_nested(s))
try
    Meta.parse(s); println("Meta.parse returned")
catch e
    println("Meta.parse threw ", typeof(e))
    bt = catch_backtrace()
    fr = unique(string.(getproperty.(stacktrace(bt), :func)))
    println("distinct frames (first 12): ", first(fr, 12))
end
