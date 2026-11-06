# Round trips of everything val2str writes, plus the range literals that must stay accepted (adopted from the
# A2 review probe reviews/8fe6120/probe_roundtrip.jl).

@enum RTColor RT_red RT_blue
struct RTStruct; a::Int; b::Float64; end

# val2str(v) -> str2val -> val2str must give the same text (hash stability); `same` also checks the value.
function rt(v; same = true)
    s = val2str(v)
    w = str2val(s)
    ok = val2str(w) == s && (!same || (isequal(w, v) && typeof(w) == typeof(v)))
    ok || println("  no round trip: ", repr(v), " -> ", repr(s), " -> ", repr(w), " :: ", typeof(w))
    return ok
end

@testset "val2str round trips" begin
    nums = Any[0, -1, typemax(Int), typemin(Int) + 1,
               Int128(2)^100, typemax(Int128), big(2)^200, -big(3)^150,
               1.5, -0.0, 1e300, 5e-324, Inf, -Inf, 2//3, -7//4, 1 + 2im, 1.5 - 2.5im, 1//2 + 3//4*im]
    for v in nums
        @test rt(v)
    end
    # val2str writes these without their type (Float32/Float16 -> Float64; BigFloat -> Float64 or text):
    # only the text needs to round-trip
    # (pre-existing widenings: small Int types -> Int64, UInt64/UInt128 -> Int128/BigInt, Rational{BigInt} -> Rational{Int128})
    for v in Any[Int8(-3), UInt8(7), Int16(5), Int32(-9), UInt64(2)^63, typemax(UInt128), big(2)^70 // 3,
                 1.5f0, Float16(0.25), NaN32, Inf16, big(1.5), Complex{Float32}(1, 2), Complex{BigInt}(1, 2)]
        @test rt(v; same = false)
    end
    @test isnan(str2val(val2str(NaN)))
    for v in Any["text", "a b", :sym, Symbol("a b"), 'x', Float64, Int, Vector{Float64}, Matrix{Int},
                 Array{Int, 3}, NTuple{3, Int}, NTuple{256, Int}, Tuple{Int, String}, Dict{Symbol, Any}, Val{3},
                 Union{Int, Nothing}, SVector{3, Float64}, SMatrix{2, 2, Float64, 4}, Complex{Float64}, Rational{BigInt}]
        @test rt(v)
    end
    for v in Any[(1, 2), (1,), (), (true, false), (true,), (1, "a", :b, 2.5), ((1, 2), (3, (4,))), (nothing, 1)]
        @test rt(v; same = !any(x -> x === nothing, v))
    end
    for v in Any[[1, 2, 3], Float64[], Any[], [1.0, NaN], ["a", "b"], [:a, :b], [true, false], Any[1, "a", :b],
                 [[1, 2], [3]], [Float32[1, 2]], Vector{Int}[[1], [2, 3]], [(1, 2), (3, 4)], [1 2; 3 4],
                 zeros(2, 1, 3), reshape(Float64[], 0, 3), reshape(collect(1:24), 2, 3, 4), [[1 2; 3 4]],
                 Matrix{Float64}[[1.0 2.0]], Int8[1, 2], UInt8[0xff], BigInt[1, big(2)^100], [1//2, 3//4], [1 + 2im],
                 [ntuple(i -> 1.0, 4)], [ntuple(i -> i, 256)], ["a" "b"; "c" "d"], [2.0;;; 3.0], [SVector(1.0, 2.0)],
                 [SVector{3, Int}(1, 2, 3)], [SMatrix{2, 2}(1.0, 2.0, 3.0, 4.0)]]
        @test rt(v; same = !(eltype(v) <: Float32))
    end
    for v in Any[SVector(1.0, 2.0), SA[1, 2, 3], SMatrix{2, 2}(1, 2, 3, 4), MVector(1.0, 2.0)]
        @test rt(v; same = false)   # written as plain arrays
    end
    for v in Any[Dict(:a => 1, :b => [10, 20]), Dict{String, Float64}("x" => 1.5), Dict{Symbol, Any}(),
                 Dict(1 => (1, 2)), Dict(:a => Dict(:b => 1)), Dict{Tuple{Int, Int}, Symbol}((1, 2) => :x)]
        @test rt(v)
    end
    for v in Any[Val(3), Val(:x), Val(2^62), Val((1, 2)), Val(true), Val(Float64)]
        @test rt(v)
    end
    @test rt(nothing; same = false) && rt(missing; same = false)
    @test rt(RT_red; same = false) && rt(RTStruct(1, 2.0); same = false)
    # PDEStudio's typed texts (`_typed_text`): SA{T}[...] and f0 literals
    @test str2val("SA{Float64}[1.0, 2.0]") === SA{Float64}[1.0, 2.0]
    @test str2val("(SA{Float64}[1.0], 1.5f0, Float16(1.5))") === (SA{Float64}[1.0], 1.5f0, Float16(1.5))
    @test str2val("Any[SA{Int64}[1, 2], 0.5f0]") == Any[SA[1, 2], 0.5f0]
    @test str2val("SVector{2, Float64}[Float64[1.0, 2.0]]") == [SVector(1.0, 2.0)]
end

@testset "ranges on their own" begin
    for (s, v) in ("1:10" => 1:10, "0:0.1:1" => 0:0.1:1, "-5:5" => -5:5, "(1:10)" => 1:10, " 1 : 10 " => 1:10,
                   "10:-1:1" => 10:-1:1, "1:0" => 1:0, "1:10^6" => 1:10^6, "0.0:0.25:1.0" => 0.0:0.25:1.0,
                   "1//2:1//2:2" => 1//2:1//2:2, "-1:-1:-5" => -1:-1:-5, "2^3:2^4" => 8:16, "1.5:3" => 1.5:3,
                   "BigInt(1):BigInt(5)" => BigInt(1):BigInt(5), "0:π/4:π" => 0:π/4:π)
        w = str2val(s)
        @test w isa AbstractRange && w == v
    end
    @test str2val("1:10^6+1") isa String
    # inside anything they are text now
    for s in ("[1:3]", "(1:3,)", "(1:3, 2)", "Any[1:3]", "Vector{Int}[1:3]", "Dict(:a => 1:3)", ":a => 1:3",
              "reshape(1:4, (2, 2))", "Val{1:3}()", "Dict{Int, UnitRange{Int}}(1 => 1:2)", "2 * (1:3)", "-(1:3)",
              "Float64(1:3)", "SA{Int}[1:3]", "[(1:2)]", "((1:2),)")
        @test str2val(s) isa String
    end
end
