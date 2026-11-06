using Test, PDEStudioCore
const S = PDEStudioCore

timed(s) = (t = @elapsed(v = str2val(s)); (v, t))

@testset "reshape of ranges (cost of _literal_size)" begin
    for s in ["reshape(1:6, (2, 3))", "reshape(1:10^6, (1000, 1000))", "reshape(1:(10^6+1000), (1001, 1000))",
              "reshape(1:10^8, (10^4, 10^4))", "reshape(1:10^9, (10^4, 10^5))"]
        v, t = timed(s)
        println(rpad(s, 45), " -> ", typeof(v), "  ", round(t; digits = 3), " s")
    end
    # time per element of the sum, to extrapolate to reshape(1:2^62, (2^31, 2^31))
    A = reshape(1:10^9, (10^4, 10^5))
    t = @elapsed S._literal_size(A)
    println("_literal_size of 1e9-element reshape: $t s -> 2^62 elements ≈ $(t * 2.0^62 / 1e9 / 3600 / 24 / 365) years")
end

@testset "legit values" begin
    for v in Any[rand(1000), rand(10, 10), (1, 2.0, "a"), Dict(:a => [1, 2], :b => (1:3,)), Any[], (), Dict{Symbol,Any}(),
                 [Int[], Int[]], fill(1.0, 10^6), fill(1.0, 10^6 + 1), fill(1.0, 1001, 1000), [rand(500_001), rand(500_000)]]
        n = S._normalize_param(v)
        println(rpad(summary(v), 45), " -> ", typeof(n), "  roundtrip = ", n isa String ? false : isequal(n, v))
    end
    t = @elapsed str2val(val2str(Any[float(i) for i in 1:10^6]))
    println("str2val of a 1e6 Any vector: $t s; _literal_size: ", @elapsed(S._literal_size(Any[float(i) for i in 1:10^6])))
    @test str2val("1:10^6") == 1:10^6
    @test str2val("(1:500000, 1:500000)") isa Tuple
    @test str2val("(1:500000, 1:500001)") isa String
    @test str2val("0:0.1:1") == 0:0.1:1
    @test str2val("Dict()") == Dict()
    @test str2val("[]") == Any[]
end
