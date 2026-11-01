"""
    solve_advection_1d(params) -> ESimData

Linear advection ``u_t + c\\,u_x = 0`` on the periodic interval ``[0, 1)`` with ``u(x, 0) = \\sin(2\\pi x)``, `N`
cells, end time `T`, time step from the CFL number `cfl` and the scheme `:scheme`:
- `"upwind"`: first order, ``u_i - \\nu (u_i - u_{i-1})`` (for ``c > 0``), smears the wave;
- `"lax_friedrichs"`: first order, central, even more diffusive;
- `"lax_wendroff"`: second order, dispersive (the wave lags behind).
"""
function solve_advection_1d(params::ParamDict)
    N, c, T, cfl = params[:N], params[:c], params[:T], params[:cfl]
    scheme = params[:scheme]
    dx = 1.0 / N
    x = collect(range(0.0, step = dx, length = N))
    t, dt = _time_grid(T, cfl * dx / abs(c))
    ν = c * dt / dx                                   # the Courant number of the (slightly shortened) step

    u = zeros(SVector{1, Float64}, N, length(t))
    v = sin.(2π .* x)
    w = similar(v)
    u[:, 1] .= SVector.(v)
    for n in 1:(length(t) - 1)
        for i in 1:N
            l, r = v[mod1(i - 1, N)], v[mod1(i + 1, N)]
            w[i] = if scheme == "upwind"
                v[i] - ν * (v[i] - l)
            elseif scheme == "lax_friedrichs"
                (l + r) / 2 - ν / 2 * (r - l)
            elseif scheme == "lax_wendroff"
                v[i] - ν / 2 * (r - l) + ν^2 / 2 * (r - 2v[i] + l)
            else
                throw(ArgumentError("unknown scheme $(repr(scheme))"))
            end
        end
        v, w = w, v
        u[:, n + 1] .= SVector.(v)
    end
    return create_sim_data(x, u, t, params)           # dims (:x, :t)
end

"""
    exact_advection_1d(params)

The exact solution of [`solve_advection_1d`](@ref): ``u(x, t) = \\sin(2\\pi (x - c\\,t))``.
"""
exact_advection_1d(params::ParamDict) = xt -> SVector(sin(2π * (xt[1] - params[:c] * xt[2])))

"""
    test_advection_1d() -> SimulationConfig

Linear advection of a sine wave ([`solve_advection_1d`](@ref)) with three schemes and the exact solution, swept
over the CFL number (at `cfl = 1` upwind and Lax–Wendroff are exact; Lax–Friedrichs isn't).
"""
function test_advection_1d()
    shared = create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :sim_func_name => :solve_advection_1d)
    methods = create_method_dict(:exact => create_param_dict(),
                                 :upwind => create_param_dict(:scheme => "upwind"),
                                 :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs"),
                                 :lax_wendroff => create_param_dict(:scheme => "lax_wendroff"))
    varied = create_varied_dict(:cfl => [0.25, 0.5, 0.75, 1.0])
    return SimulationConfig(shared, methods, [:exact, :upwind, :lax_friedrichs, :lax_wendroff];
                            varied = varied, reference = :exact_advection_1d)
end
