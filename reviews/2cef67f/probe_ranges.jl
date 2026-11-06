using PDEStudioCore, Test
const s2v = PDEStudioCore.str2val
function show1(s)
    t = @elapsed(a = @allocated(v = s2v(s)))
    println(rpad(s, 46), " => ", rpad(v isa String ? "String" : string(typeof(v)), 60)[1:60], "  len=", v isa String ? "-" : (v isa AbstractArray ? length(v) : "-"),
            "  t=", round(t; digits = 3), "  alloc=", a)
    v
end
cases = [
 "1:10^6", "1:10^6+1", "0:10^6-1", "0:10^6", "10^6:-1:1", "10^6:-1:0", "10:1", "1:0", "5:4",
 "typemin(Int):typemax(Int)", "-9223372036854775808:9223372036854775807", "0:2:9223372036854775807",
 "0x0000000000000000:0xffffffffffffffff", "0x00:0xff", "Int8(-128):Int8(127)", "UInt8(0):UInt8(255)",
 "Int128(1):Int128(10)^7", "1:big(10)^6", "1:big(10)^6+1", "big(1):big(2)^200",
 "1.0:1e6", "1.0:1e6+1", "1.0:2.0^62", "1.0:2.0^70", "0.0:1e-300:1.0", "0.0:0.1:1e5", "0.0:0.1:1e5+0.1", "1e6:-1.0:1.0", "1e6:-1.0:0.0",
 "Float32(1):Float32(2)^30", "Float16(1):Float16(2000)", "1.0:Inf", "NaN:1.0", "1.0:0.0:5.0", "big(1.0):big(1e6)", "big(1.0):big(1e7)",
 "'a':'z'", "'\\0':'\\U10ffff'", "'\\0':'\\UF4240'", "'\\0':'\\UF423F'", "'a':2:'z'",
 "1//1:10^6//1", "1//1:(10^6+1)//1", "1//2:1//3:10^6//1", "0//1:1//10^9:1//1", "big(1)//1:big(10)^7//1",
 "1:2:typemax(Int)", "typemax(Int)-1:typemax(Int)", "Int8(1):Int8(2):Int8(100)",
 "(1+0im):(5+0im)", "true:true", "false:true",
]
for c in cases
    try show1(c) catch e println(rpad(c, 46), " => THROWS ", e) end
end
