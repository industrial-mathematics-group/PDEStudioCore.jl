using PDEStudioCore
const P = PDEStudioCore
const s2v = P.str2val
function show1(s; rt = true)
    t = @elapsed(a = @allocated(v = try s2v(s) catch e e end))
    r = v isa String ? "String" : v isa Exception ? "THROWS $(typeof(v))" : string(typeof(v), " size=", size(v))
    extra = ""
    if rt && !(v isa Union{String, Exception})
        extra = try
            s2 = P.val2str(v); v2 = s2v(s2)
            "  roundtrip=" * string(isequal(v2, v) && typeof(v2) == typeof(collect(v)) || isequal(v2, v)) * "  hash ok=" * string(P.calculate_hash(Dict(:x => v)) isa String)
        catch e
            "  val2str/hash THROWS " * sprint(showerror, e)[1:min(end, 60)]
        end
    end
    println(rpad(s[1:min(end, 50)], 50), " => ", rpad(r, 55)[1:55], " t=", round(t; digits = 3), extra)
end
for s in ["reshape(1:6, (2, 3))", "reshape(1:0, (2^32, 2^32))", "reshape(1:0, (2^31, 2^31, 4))", "reshape(1:0, (0, 2^62, 2^62))",
          "reshape(1:0, (2^62, 2^62, 0))", "reshape(1:0, (0, -1))", "reshape(1:0, (-1, 0))", "reshape(1:6, (-2, -3))",
          "reshape(1:0, (-2^32, 2^32))", "reshape(Int64[], (0, 5))", "reshape(1:1, ())", "reshape(Int64[1], ())",
          "reshape(1:6, (BigInt(2), BigInt(3)))", "reshape(1:1, (true, true))", "reshape(1:10^6, (1000, 1000))",
          "reshape(1:10^6, (1000, 1001))", "reshape(1:6, (6,))", "reshape(1:4, (2, 2.0))", "reshape(1:6, (Int8(2), 3))",
          "reshape(1:0, (UInt64(2)^63, 2))", "reshape(1:0, (9223372036854775807, 0))", "reshape(Float64[], (2^40, 0))",
          "reshape(1:0, (Int128(2)^64, 0))", "reshape(1:0, (0, Int128(2)^64))"]
    show1(s)
end
println("--- many dimensions (compile time)")
for n in (10, 50, 100, 200)
    s = "reshape(1:1, (" * join(fill("1", n), ", ") * "))"
    t = @elapsed(v = s2v(s))
    th = @elapsed(try P.calculate_hash(Dict(:x => v)) catch e println("  hash throws ", typeof(e)) end)
    println("ndims=$n: ", length(s), " chars, str2val ", round(t; digits = 2), " s, ", v isa String ? "String" : "array", "; hash ", round(th; digits = 2), " s")
end
