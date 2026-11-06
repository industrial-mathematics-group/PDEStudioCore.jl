# Probe: normalisation round trips, hash collisions, str2val surface
using Test, PDEStudioCore, StaticArrays, Logging
global_logger(ConsoleLogger(stderr, Logging.Warn))
set_save_path!(mktempdir())

@testset "normalisation of nothing/missing inside containers" begin
    c = get_clean_params(create_param_dict(:a => (1, nothing), :b => [1, missing], :c => [nothing]))
    @show c[:a] typeof(c[:a]) c[:b] typeof(c[:b]) c[:c]
    @test_broken c[:a] === (1, nothing)          # becomes (1, Nothing): the *type*, not the value
    @test_broken isequal(c[:b], [1, missing])    # becomes the String "Union{Missing, Int64}[1, Missing]"
    # and the value nothing and the type Nothing share a hash
    @test calculate_hash(Dict(:a => (1, nothing))) == calculate_hash(Dict(:a => (1, Nothing)))
end

@testset "hash collisions between strings and other values" begin
    @test calculate_hash(Dict(:k => "1")) == calculate_hash(Dict(:k => 1))
    @test calculate_hash(Dict(:k => ":upwind")) == calculate_hash(Dict(:k => :upwind))
    @test calculate_hash(Dict(:k => "Float64")) == calculate_hash(Dict(:k => Float64))
    @test calculate_hash(Dict(:k => "<empty>")) == calculate_hash(Dict(:k => ""))
    @test calculate_hash(Dict(:k => 0.1f0)) == calculate_hash(Dict(:k => 0.1))      # but values differ
    @test get_clean_params(Dict(:k => 0.1f0))[:k] === 0.1 && Float64(0.1f0) != 0.1
end

@testset "save_sim_data mutates the caller's params" begin
    p = create_param_dict(:h => 0.1f0, :tag => "mut")
    sim = create_sim_data([0.0, 1.0], [1.0, 2.0], p)
    save_sim_data(sim; verbose = false)
    @show sim.params[:h] typeof(sim.params[:h])
    @test sim.params[:h] === 0.1   # was 0.1f0 before saving
end

@testset "str2val returns live global objects (EnvDict)" begin
    v = str2val("EnvDict()")
    @show typeof(v)
    @test v === ENV
end

@testset "str2val resource use: arithmetic on BigInt literals is unbounded" begin
    t = @elapsed v = str2val("BigInt(3)^(10^7)")
    @show t ndigits(v)
    @test v isa BigInt   # 10^8 or 10^10 here would take minutes / GBs of memory
end
