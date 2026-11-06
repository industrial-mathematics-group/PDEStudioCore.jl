using Test, PDEStudioCore, StaticArrays
set_save_path!(mktempdir())
@testset "probe_misc" begin

@testset "tuple sweep keeps element types" begin
    tasks, _ = generate_method_tasks(create_param_dict(:periodic => (true, false)), [:periodic__x], [[false, true]])
    @show [t[:periodic] for t in tasks]
    @test all(t -> t[:periodic] isa Tuple{Bool, Bool}, tasks)
    tasks8, _ = generate_method_tasks(create_param_dict(:Ns => (Int32(4), Int32(5))), [:Ns__x], [[Int32(8)]])
    @show typeof(tasks8[1][:Ns])
end

@testset "hash collisions between strings and numbers" begin
    @test calculate_hash(create_param_dict(:a => "1.0")) != calculate_hash(create_param_dict(:a => 1.0))
    @test calculate_hash(create_param_dict(:a => ":upwind")) != calculate_hash(create_param_dict(:a => :upwind))
end

@testset "SVector parameters" begin
    p = create_param_dict(:v => SVector(1.0, 2.0))
    c = get_clean_params(p)
    @show c[:v] typeof(c[:v])
    @test c[:v] isa AbstractVector
end

@testset "nested big powers" begin
    t = @elapsed v = str2val("(big\"10\"^10000)^10000")
    @show typeof(v) t
    v isa BigInt && @show ndigits(v)
    @test !(v isa BigInt)
end
end
