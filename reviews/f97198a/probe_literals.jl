using PDEStudioCore, Test
const P = PDEStudioCore
@testset "typical literals still parse" begin
    for (s, v) in ["2^10" => 1024, "10^6" => 10^6, "2.0^-3" => 0.125, "1e-3" => 1e-3, "1//3" => 1//3,
                   "(1//2)^10" => (1//2)^10, "BigInt(2)^100" => big(2)^100, "BigInt(10)^(2^18)" => big(10)^(2^18),
                   "1:10" => 1:10, "0:0.1:1" => 0:0.1:1, "1:10^6" => 1:10^6, "2π" => 2π, "im^2" => im^2,
                   "1.5^(10^7)" => 1.5^(10^7), "(1+2im)^3" => (1+2im)^3]
        @test isequal(str2val(s), v)
    end
    # values val2str writes round-trip
    for v in (1, -3, 0.1, 1//3, big(2)^200, big"1.5", Int128(2)^100, 1 + 2im, 0.5 + 1.5im, π, (1, 2.0), [1, 2], Int32(5),
              UInt8(3), true, 1:3, collect(0:0.001:1), Float16(0.5), Inf, NaN, -Inf32)
        @test isequal(str2val(val2str(v)), v) || (println("no roundtrip: ", repr(v), " -> ", repr(str2val(val2str(v)))); false)
    end
end
@testset "rejected (expect String)" begin
    for s in ["2^(10^6)", "im^(10^7)", "0:1e-6:1.5", "1:(10^6+1)"]
        r = str2val(s); println(rpad(s, 20), " -> ", typeof(r))
    end
end
@testset "overflow in the size product" begin
    # bits(BigInt(3)) == 2; 2 * 2^62 wraps to typemin(Int) < limit
    e = 2^62
    @show e * P._exact_bits(big(3)) (abs(e) * P._exact_bits(big(3)) > P._MAX_LITERAL_BITS)
    e3 = 6148914691236517206  # 3e wraps to 2
    @show e3 * P._exact_bits(big(5)) (abs(e3) * P._exact_bits(big(5)) > P._MAX_LITERAL_BITS)
    @show abs(typemin(Int)) * 2
end
@testset "tuple of ranges: per-range cap only" begin
    s = "(" * join(fill("1:10^6", 20), ", ") * ")"
    @show length(s)
    v = str2val(s); @show typeof(v)
    t = @elapsed P._param_hash(Dict(:r => v)); @show t
end
