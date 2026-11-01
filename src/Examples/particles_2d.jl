"""
    solve_particles_2d(params) -> LSimData

Particles in a solid-body rotation ``\\dot x = -\\omega y``, ``\\dot y = \\omega x`` (one revolution per `period`):
a `K`×`K` grid of particles in ``[-1, 1]^2`` moved for the time `T` with the time step `dt` and the integrator
`:integrator`:
- `"euler"`: explicit Euler, first order; every step pushes the particles outwards by the factor
  ``\\sqrt{1 + (\\omega\\,\\Delta t)^2}``, so they spiral out;
- `"rk2"`: the midpoint rule, second order (spirals out slowly);
- `"rk4"`: the classical Runge–Kutta method, fourth order (spirals in, very slowly).

Each particle carries its initial distance from the centre, which the exact flow keeps: the reference is the
distance of the particle's current position, so the error statistics measure the radial drift of the integrator.
Lagrangian data: in PDEStudio, `set_mode!(:lagrangian)` first.
"""
function solve_particles_2d(params::ParamDict)
    K, T, dt, period = params[:K], params[:T], params[:dt], params[:period]
    integrator = params[:integrator]
    integrator in ("euler", "rk2", "rk4") || throw(ArgumentError("unknown integrator $(repr(integrator))"))
    ω = 2π / period
    t, h = _time_grid(T, dt)
    velocity(p) = SVector(-ω * p[2], ω * p[1])
    function step(p)
        integrator == "euler" && return p + h * velocity(p)
        integrator == "rk2" && return p + h * velocity(p + h / 2 * velocity(p))
        k1 = velocity(p)
        k2 = velocity(p + h / 2 * k1)
        k3 = velocity(p + h / 2 * k2)
        k4 = velocity(p + h * k3)
        return p + h / 6 * (k1 + 2k2 + 2k3 + k4)
    end

    grid = range(-1.0, 1.0, length = K)
    x = [vec([SVector(a, b) for a in grid, b in grid])]
    r0 = [SVector(hypot(p...)) for p in x[1]]
    for _ in 2:length(t)
        push!(x, step.(x[end]))
    end
    return create_sim_data(x, [copy(r0) for _ in t], t, params)   # dims (:x, :y, :t)
end

"""
    exact_particles_2d(params)

The reference of [`solve_particles_2d`](@ref): the distance from the centre, which every particle keeps in the
exact flow.
"""
exact_particles_2d(params::ParamDict) = xyt -> SVector(hypot(xyt[1], xyt[2]))

"""
    test_particles_2d() -> SimulationConfig

Particles in a rotating flow ([`solve_particles_2d`](@ref)), two revolutions with three integrators, swept over the
time step. Lagrangian data (in PDEStudio: `set_mode!(:lagrangian)` first).
"""
function test_particles_2d()
    shared = create_param_dict(:K => 10, :T => 2.0, :period => 1.0, :dt => 0.05, :sim_func_name => :solve_particles_2d)
    methods = create_method_dict(:euler => create_param_dict(:integrator => "euler"),
                                 :rk2 => create_param_dict(:integrator => "rk2"),
                                 :rk4 => create_param_dict(:integrator => "rk4"))
    varied = create_varied_dict(:dt => [0.05, 0.02, 0.01])
    return SimulationConfig(shared, methods, [:euler, :rk2, :rk4]; varied = varied, reference = :exact_particles_2d)
end
