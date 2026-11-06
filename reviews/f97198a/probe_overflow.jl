using PDEStudioCore
s = ARGS[1]
t = @elapsed r = str2val(s)
println(s, " -> ", typeof(r), " in ", round(t; digits = 2), " s", r isa String ? "" : string(", bits = ", PDEStudioCore._exact_bits(r)))
