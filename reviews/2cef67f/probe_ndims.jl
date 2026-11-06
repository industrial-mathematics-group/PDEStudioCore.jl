using PDEStudioCore
const P = PDEStudioCore
for n in parse.(Int, ARGS)
    s = "reshape(1:1, (" * join(fill("1", n), ", ") * "))"
    t = @elapsed(v = P.str2val(s))
    th = @elapsed(try P.calculate_hash(Dict(:x => v)) catch e println("  hash throws ", typeof(e)) end)
    st = "(" * join(fill("1", n), ", ") * ")"
    tt = @elapsed(w = P.str2val(st))
    tth = @elapsed(P.calculate_hash(Dict(:x => w)))
    println("n=$n: reshape ", length(s), " chars: str2val ", round(t; digits = 2), " s (", v isa String ? "String" : "array", "), hash ", round(th; digits = 2),
            " s | tuple: str2val ", round(tt; digits = 2), " s, hash ", round(tth; digits = 2), " s")
end
