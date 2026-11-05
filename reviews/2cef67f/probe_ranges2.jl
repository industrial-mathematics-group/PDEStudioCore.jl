using PDEStudioCore
const s2v = PDEStudioCore.str2val
function show1(s)
    t = @elapsed(a = @allocated(v = s2v(s)))
    println(rpad(s[1:min(end, 60)], 60), " => ", rpad(v isa String ? "String" : string(typeof(v)), 50)[1:50], "  len=", v isa AbstractArray ? length(v) : "-",
            "  t=", round(t; digits = 3), "  alloc=", a)
    v
end
for c in ["9223372036854775806:9223372036854775807", "1:2:9223372036854775807", "-9223372036854775807:2:9223372036854775807",
          "BigInt(1):BigInt(10)^6", "BigInt(1):BigInt(10)^6+1", "BigInt(1):BigInt(2)^200", "BigInt(2)^200:-1:BigInt(1)",
          "BigFloat(1):BigFloat(1e6)", "BigFloat(1):BigFloat(1e6)+1", "BigFloat(1):BigFloat(1e30)",
          "BigInt(1)//1:BigInt(10)^7//1", "Int128(1):Int128(10)^6", "Int128(1):Int128(10)^6+1", "-170141183460469231731687303715884105728:170141183460469231731687303715884105727",
          "UInt128(0):340282366920938463463374607431768211455", "0x00000000:0xffffffff", "Int32(0):Int32(2)^30",
          "1:1:0", "1:-1:2", "10^6:1:1", "1.0:-1.0:2.0", "1:0.5:5", "1:0.5:500001", "1:0.5:500000.5"]
    try show1(c) catch e println(rpad(c, 60), " => THROWS ", e) end
end
