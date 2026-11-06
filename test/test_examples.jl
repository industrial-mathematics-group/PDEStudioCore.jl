# The built-in examples (src/Examples): every test_* config runs, and every solver shows what its docstring says.
using PDEStudioCore.Examples: solve_advection_1d, exact_advection_1d, solve_burgers_1d, solve_heat_1d, exact_heat_1d,
    solve_heat_2d, exact_heat_2d, solve_poisson_2d, exact_poisson_2d, solve_particles_2d

# Run the solver of `config` for one method and one value of the swept parameter
function run_example(config, method; kw...)
    params = merge(copy(config.shared), config.methods[method], Dict{Symbol, Any}(kw))
    return PDEStudioCore.resolve_dynamic_function(params[:sim_func_name])(params)
end
# Maximum error of the last snapshot of an Eulerian run against an exact solution
function final_error(sim, exact)
    pts = Iterators.product(sim.axes[1:end-1]...)
    t = sim.axes[end][end]
    return maximum(abs(sim.u[Tuple(I)..., end][1] - exact(SVector(p..., t))[1])
                   for (I, p) in zip(CartesianIndices(size(sim.u)[1:end-1]), pts))
end

@testset "Examples" begin
    @testset "Every example config runs" begin
        for example in (test_advection_1d, test_burgers_1d, test_heat_1d, test_heat_2d, test_poisson_2d, test_particles_2d)
            config = example()
            @test config isa SimulationConfig
            @test isnothing(run_all_simulations(config; parallel = true, calculate_stats = true))
            # the solver and the reference are found by name, without set_target_module!
            @test PDEStudioCore.resolve_dynamic_function(config.shared[:sim_func_name]) isa Function
            isnothing(config.reference) || @test PDEStudioCore.resolve_dynamic_function(config.reference) isa Function
        end
    end

    @testset "Advection: order and the exact CFL number" begin
        cfg = test_advection_1d()
        ex = exact_advection_1d(cfg.shared)
        err(m, cfl) = final_error(run_example(cfg, m; cfl), ex)
        @test err(:upwind, 1.0) < 1e-12 && err(:lax_wendroff, 1.0) < 1e-12      # exact shifts at ν = 1
        @test err(:lax_friedrichs, 1.0) < 1e-12                                 # (l + r)/2 - (r - l)/2 = l
        @test err(:lax_wendroff, 0.5) < err(:upwind, 0.5) < err(:lax_friedrichs, 0.5)
    end

    @testset "Burgers: conservative schemes keep the mass" begin
        cfg = test_burgers_1d()
        mass(m) = (sim = run_example(cfg, m); sum(u[1] for u in sim.u[:, end]) - sum(u[1] for u in sim.u[:, 1]))
        @test abs(mass(:godunov)) < 1e-10 && abs(mass(:lax_friedrichs)) < 1e-10
        @test abs(mass(:nonconservative_upwind)) > 1e-3
    end

    @testset "Heat 1D: explicit stability limit, Crank–Nicolson most accurate" begin
        cfg = test_heat_1d()
        ex = exact_heat_1d(cfg.shared)
        err(m, r) = final_error(run_example(cfg, m; r), ex)
        @test err(:explicit, 0.6) > 1                                            # unstable above r = 1/2
        @test err(:implicit, 0.6) < 1e-2 && err(:crank_nicolson, 0.6) < 1e-3
        @test err(:crank_nicolson, 0.4) < err(:implicit, 0.4)
    end

    @testset "Heat 2D: explicit stability limit, ADI stable" begin
        cfg = test_heat_2d()
        ex = exact_heat_2d(cfg.shared)
        err(m, r) = final_error(run_example(cfg, m; r), ex)
        @test err(:explicit, 0.3) > 1
        @test err(:explicit, 0.25) < 1e-3 && err(:adi, 0.3) < 1e-3
    end

    @testset "Poisson: SOR reaches the discretisation error, Jacobi doesn't" begin
        cfg = test_poisson_2d()
        ex = exact_poisson_2d(cfg.shared)
        err(m) = final_error(run_example(cfg, m), ex)
        @test err(:sor) < 2e-3                                                   # O(h²) at N = 32
        @test err(:jacobi) > err(:gauss_seidel) > 10 * err(:sor)
        @test run_example(cfg, :sor).axes[end] == 0:cfg.shared[:iterations]          # t counts the iterations
    end

    @testset "Particles: Euler spirals out, RK4 keeps the radius" begin
        cfg = test_particles_2d()
        drift(m) = (sim = run_example(cfg, m); maximum(abs(hypot(p...) - u[1]) for (p, u) in zip(sim.x[end], sim.u[end])))
        @test drift(:euler) > 1 > 0.1 > drift(:rk2) > 0.01 > 1e-3 > drift(:rk4)               # at dt = 0.05
    end
end
