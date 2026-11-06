using PDEStudioCore
v = str2val("(1:9223372036854775807, 1:9223372036854775807)")
println("str2val -> ", typeof(v)); flush(stdout)
t = @elapsed try
    PDEStudioCore._param_hash(Dict(:a => v))
catch e
    println("error: ", typeof(e))
end
println("hash took $t s")
