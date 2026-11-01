"""
    solve_burgers_1d(params) -> ESimData

Inviscid Burgers ``u_t + (u^2/2)_x = 0`` on the periodic interval ``[0, 1)`` with ``u(x, 0) = 1 + \\frac12 \\sin(2\\pi x)``:
the wave steepens and a shock forms at ``t = 1/\\pi``. `N` cells, end time `T`, time step from `cfl`, scheme
`:scheme`:
- `"lax_friedrichs"`: conservative, first order, diffusive;
- `"godunov"`: conservative, first order, with the exact Riemann flux (sharp shock);
- `"nonconservative_upwind"`: upwind for ``u_t + u\\,u_x = 0``. Smooth solutions are fine, but the shock moves at
  the wrong speed and mass is lost: only conservative schemes converge to the right weak solution.
"""
function solve_burgers_1d(params::ParamDict)
    N, T, cfl = params[:N], params[:T], params[:cfl]
    scheme = params[:scheme]
    dx = 1.0 / N
    x = collect(range(0.0, step = dx, length = N))
    t, dt = _time_grid(T, cfl * dx / 1.5)             # |u| ≤ 1.5 for all times (maximum principle)
    λ = dt / dx

    f(u) = u^2 / 2
    function flux(l, r)                                # numerical flux at the face between l and r
        if scheme == "lax_friedrichs"
            return (f(l) + f(r)) / 2 - (r - l) / (2λ)
        else                                           # Godunov: the exact Riemann solution at the face
            return l > r ? max(f(l), f(r)) : (l > 0 ? f(l) : r < 0 ? f(r) : 0.0)
        end
    end

    u = zeros(SVector{1, Float64}, N, length(t))
    v = 1 .+ sin.(2π .* x) ./ 2
    w = similar(v)
    u[:, 1] .= SVector.(v)
    for n in 1:(length(t) - 1)
        for i in 1:N
            l, c, r = v[mod1(i - 1, N)], v[i], v[mod1(i + 1, N)]
            w[i] = if scheme == "nonconservative_upwind"
                c - λ * c * (c > 0 ? c - l : r - c)
            elseif scheme in ("lax_friedrichs", "godunov")
                c - λ * (flux(c, r) - flux(l, c))
            else
                throw(ArgumentError("unknown scheme $(repr(scheme))"))
            end
        end
        v, w = w, v
        u[:, n + 1] .= SVector.(v)
    end
    return create_sim_data(x, u, t, params)
end

"""
    test_burgers_1d() -> SimulationConfig

A shock forming in inviscid Burgers ([`solve_burgers_1d`](@ref)): two conservative schemes and a non-conservative one
(wrong shock speed, see the `mass` statistic), swept over the grid size. There is no exact solution after the shock
forms, so there is no reference.
"""
function test_burgers_1d()
    shared = create_param_dict(:N => 100, :T => 0.8, :cfl => 0.8, :sim_func_name => :solve_burgers_1d)
    methods = create_method_dict(:lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs"),
                                 :godunov => create_param_dict(:scheme => "godunov"),
                                 :nonconservative_upwind => create_param_dict(:scheme => "nonconservative_upwind"))
    varied = create_varied_dict(:N => [50, 100, 200])
    return SimulationConfig(shared, methods, [:lax_friedrichs, :godunov, :nonconservative_upwind]; varied = varied)
end
