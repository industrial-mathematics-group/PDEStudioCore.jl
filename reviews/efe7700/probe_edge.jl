# Probe: Float32 / static / singleton-axis datasets through stats, save/load and conversions
using Test, PDEStudioCore, StaticArrays, Logging
global_logger(ConsoleLogger(stderr, Logging.Warn))
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())
@testset "Float32 transient 2D" begin
    x = Float32.(range(0, 1, length = 9)); y = Float32.(range(0, 2, length = 5)); t = Float32[0, 0.5, 1]
    s = create_sim_data((x, y), [SVector(xi + yi + ti, 1f0) for xi in x, yi in y, ti in t], t, create_param_dict(:tag => "f32"))
    @test s isa ESimData{3, 2, 2, Float32}
    calculate_all_stats!(s, xyt -> SVector(xyt[1] + xyt[2] + xyt[3], 1.0))
    l = load_sim_data(s.params)
    @test l isa ESimData{3, 2, 2, Float32} && eltype(l.stats[:mass]) == SVector{2, Float32}
    @test all(e -> all(abs.(e) .< 1f-5), l.stats[:l1error])
    # mass of component 2 (== 1 everywhere) = number of nodes * dx * dy (rectangle rule incl. both ends)
    @show l.stats[:mass][1][2]  (9 * 5) * (1/8) * (2/4)
    L = load_sim_data(s.params, :lagrangian); @test L isa LSimData{3, 2, 2, Float32}
    E = load_sim_data(s.params, :eulerian, (17, 9, 3)); @test E isa ESimData{3, 2, 2, Float32}
    E2 = convert_to_eulerian(L, (9, 5, 3)); @test maximum(abs.(first.(E2.u) .- first.(s.u))) < 1f-5
end
@testset "static 1D and singleton axes" begin
    s = create_sim_data([0.0, 0.5, 1.0], [1.0, 2.0, 3.0], create_param_dict(:tag => "static1"))
    calculate_all_stats!(s; save = false)
    @show s.stats[:mass] s.stats[:wave_height]
    @test s.stats[:mass] == SVector(3.0)       # 0.5 * (1+2+3): :time on static data -> scalar
    s1 = create_sim_data([0.3], [SVector(1.0) for _ in 1:1, _ in 1:3], [0.0, 1.0, 2.0], create_param_dict(:tag => "single"))
    calculate_all_stats!(s1; save = false)
    @test length(s1.stats[:mass]) == 3
    r = resample_eulerian(s1, (4, 3)); @test size(r.u) == (4, 3)
end
