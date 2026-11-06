using PDEStudioCore, Test
const S = PDEStudioCore
function t(s)
    v = nothing
    el = @elapsed(v = str2val(s))
    return (v isa String ? "String" : summary(v)), round(el; digits = 3)
end
# warm-up
str2val("reshape(1:4, (2, 2))"); str2val("(1:3, [1, 2])"); str2val("Dict(1 => 1:3)")
cases = [
  # overflowing range lengths
  "(-2^62-2^62):(2^62+(2^62-1))",            # typemin(Int):typemax(Int), length wraps to 0
  "(-2^62-2^62):2:(2^62+(2^62-1))",          # StepRange, 2^63 elements
  "0x0000000000000000:0xffffffffffffffff",  # UInt64 full range
  "0x00:0xff", "Int8(-128):Int8(127)",
  "Int128(1):Int128(2)^100", "BigInt(1):BigInt(2)^100",
  "0.0:1e-30:1.0", "1.0:1e19",
  # reshape edge cases
  "reshape(1:0, (2^32, 2^32))", "reshape(1:2^62, (2^31, 2^31))", "reshape(1:2^48, (2^24, 2^24))",
  "reshape(Int[], (2^32, 2^32))", "reshape(1:6, (2, 3))", "reshape(1:10^6, (1000, 1000))", "reshape(1:(10^6+1), (10^6+1, 1))",
  # nested lazy
  "((1:2^62,),)", "[1:2^62]", "Any[(1, 1:2^62)]", "Dict(1 => 1:2^62)", "Dict(1:2^62 => 1)", "1 => (2 => 1:2^62)",
  "(1:500000, 1:500000)", "(1:500000, 1:500001)", "[1:500000, 1:500000]", "Dict(1 => 1:499999, 2 => 1:499999)",
  "Dict(1 => 1:499999, 2 => 1:500000)",
  # empty containers
  "()", "Int[]", "Any[]", "Dict()", "Dict{Int, Int}()", "1:0", "(1:0, 1:0)",
  # eager collection of ranges via typed containers (memory!)
  "Vector{Float16}[0:2^24]", "Vector{Float16}[0:2^26]", "Dict{Int, Vector{Float16}}(1 => 0:2^26)",
]
for s in cases
    r = try; t(s); catch e; ("THROWS $(typeof(e))", NaN); end
    println(rpad(s, 45), " => ", r)
end
println("alloc Vector{Float16}[0:2^26]: ", @allocated(str2val("Vector{Float16}[0:2^26]")) ÷ 2^20, " MiB")
println("_literal_size(typemin(Int):typemax(Int)) = ", S._literal_size(typemin(Int):typemax(Int)), ", length = ", length(typemin(Int):typemax(Int)))
