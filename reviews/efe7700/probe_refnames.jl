# Probe: methods whose name merely contains a reference keyword are silently never run
using Test, PDEStudioCore, Logging
@testset "reference-method heuristic" begin
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :whatever, :N => 10),
                           create_method_dict(:godunov_exact_riemann => create_param_dict(:flux => "exact"),
                                              :upwind => create_param_dict(:flux => "upwind")))
    tasks = @test_logs min_level = Logging.Warn generate_tasks(cfg)   # no warning at all
    @show cfg.defaults [t[:flux] for t in tasks]
    @test length(tasks) == 1                                           # the Godunov method is dropped
end
