# Probe: docstring claims of the built-in examples
using Test, PDEStudioCore, StaticArrays
using PDEStudioCore.Examples: solve_advection_1d, exact_advection_1d, solve_burgers_1d, solve_heat_1d, exact_heat_1d,
    solve_heat_2d, exact_heat_2d, solve_poisson_2d, exact_poisson_2d, solve_particles_2d
set_save_path!(mktempdir())
run_example(config, method; kw...) = (p = merge(copy(config.shared), config.methods[method], Dict{Symbol, Any}(kw));
    PDEStudioCore.resolve_dynamic_function(p[:sim_func_name])(p))
function final_error(sim, exact)
    t = sim.axes[end][end]
    maximum(abs(sim.u[Tuple(I)..., end][1] - exact(SVector((sim.axes[d][I[d]] for d in 1:length(I))..., t))[1])
            for I in CartesianIndices(size(sim.u)[1:end-1]))
end

@testset "advection docstring: 'at cfl = 1 ... Lax–Friedrichs isn't' exact" begin
    cfg = test_advection_1d(); ex = exact_advection_1d(cfg.shared)
    for m in (:upwind, :lax_friedrichs, :lax_wendroff)
        e = final_error(run_example(cfg, m; cfl = 1.0), ex)
        println("cfl=1  $m  max error = $e")
    end
    @test final_error(run_example(cfg, :lax_friedrichs; cfl = 1.0), ex) < 1e-12   # LF IS exact at nu = 1
    for c in (0.25, 0.5, 0.75)
        println("cfl=$c  ", [(m, round(final_error(run_example(cfg, m; cfl = c), ex), sigdigits=3)) for m in (:upwind, :lax_friedrichs, :lax_wendroff)])
    end
end

@testset "burgers docstring: ~7% mass drift by t=0.8 at N=50, wrong shock speed" begin
    cfg = test_burgers_1d()
    for N in (50, 100, 200), m in (:godunov, :lax_friedrichs, :nonconservative_upwind)
        sim = run_example(cfg, m; N)
        m0 = sum(u[1] for u in sim.u[:, 1]); m1 = sum(u[1] for u in sim.u[:, end])
        # shock location: largest negative jump
        v = first.(sim.u[:, end]); d = [v[mod1(i+1, N)] - v[i] for i in 1:N]; i = argmin(d)
        println("N=$N $m: relative mass change = $(round((m1 - m0)/m0*100, sigdigits=3)) %, shock at x≈$(round(sim.axes[1][i], digits=3))")
    end
end

@testset "heat 1d/2d stability claims" begin
    c1 = test_heat_1d(); e1 = exact_heat_1d(c1.shared)
    for r in (0.25, 0.4, 0.5, 0.6), m in (:explicit, :implicit, :crank_nicolson)
        println("heat1d r=$r $m err=$(round(final_error(run_example(c1, m; r), e1), sigdigits=3))")
    end
    c2 = test_heat_2d(); e2 = exact_heat_2d(c2.shared)
    for r in (0.1, 0.25, 0.3), m in (:explicit, :adi)
        println("heat2d r=$r $m err=$(round(final_error(run_example(c2, m; r), e2), sigdigits=3))")
    end
    # temporal order of CN/ADI: refine dt at fixed fine N? (spatial error dominates) -> report ratio only
end

@testset "poisson: levels off at O(1/N^2)" begin
    c = test_poisson_2d(); ex = exact_poisson_2d(c.shared)
    for N in (16, 32), m in (:jacobi, :gauss_seidel, :sor)
        println("poisson N=$N $m err=$(round(final_error(run_example(c, m; N), ex), sigdigits=3))")
    end
end

@testset "particles: euler out, rk2 out slowly, rk4 in" begin
    c = test_particles_2d()
    for dt in (0.05, 0.02, 0.01), m in (:euler, :rk2, :rk4)
        sim = run_example(c, m; dt)
        dr = [hypot(p...) - u[1] for (p, u) in zip(sim.x[end], sim.u[end])]
        println("particles dt=$dt $m: mean radial drift = $(round(sum(dr)/length(dr), sigdigits=3))")
    end
end
