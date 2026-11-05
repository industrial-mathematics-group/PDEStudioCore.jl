using Test, PDEStudioCore, StaticArrays
PDEStudioCore.set_target_module!(@__MODULE__)
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())

function const_solver(params)
    x = collect(range(0.0, 1.0, length = 5))
    return create_sim_data(x, fill(SVector(1.0), 5, 2), [0.0, 1.0], params)
end
double_post(data) = (data.u = 2 .* data.u; true)

@testset "post-processing runs on every call" begin
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :const_solver, :n => 1); postprocess = :double_post)
    p = only(generate_tasks(cfg))
    run_all_simulations(cfg; calculate_stats = true)
    u1 = load_sim_data(p).u[1][1]
    m1 = load_sim_data(p).stats[:mass][1][1]
    run_all_simulations(cfg; calculate_stats = true)
    u2 = load_sim_data(p).u[1][1]
    @show u1 u2 m1 load_sim_data(p).stats[:mass][1][1]
    @test u2 == u1        # fails: the cached dataset is post-processed (doubled) again
    # statistics were computed before post-processing and are never refreshed
    @test m1 ≈ sum(v[1] for v in load_sim_data(p).u[:, 1]) * 0.25
end
