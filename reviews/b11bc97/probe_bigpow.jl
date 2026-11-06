using PDEStudioCore
s = ARGS[1]
t = @elapsed v = str2val(s)
println("input: ", s, "  -> ", typeof(v), "  time = ", t, v isa BigInt ? "  ndigits(base 2) = $(ndigits(v; base = 2))" : "")
