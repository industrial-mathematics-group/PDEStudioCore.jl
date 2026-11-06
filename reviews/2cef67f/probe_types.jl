using PDEStudioCore
const P = PDEStudioCore
for s in ARGS
    t = @elapsed(v = try P.str2val(s) catch e e end)
    th = @elapsed(h = try P.calculate_hash(Dict(:x => v)); "ok" catch e sprint(showerror, e)[1:min(end, 60)] end)
    tn = @elapsed(n = try P._normalize_param(v); "ok" catch e sprint(showerror, e)[1:min(end, 60)] end)
    println(rpad(s[1:min(end, 45)], 45), " => ", rpad(v isa String ? "String" : string(typeof(v))[1:min(end, 45)], 45), " t=", round(t; digits = 2),
            "  hash ", h, " ", round(th; digits = 2), " s  normalize ", n, " ", round(tn; digits = 2), " s")
end
