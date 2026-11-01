"""
    solve_heat_1d(params) -> ESimData

The heat equation ``u_t = \\kappa\\,u_{xx}`` on ``[0, 1]`` with ``u = 0`` at both ends and
``u(x, 0) = \\sin(\\pi x) + \\frac12 \\sin(3\\pi x)``, `N` intervals, end time `T` and the time step from the diffusion
number ``r = \\kappa\\,\\Delta t / \\Delta x^2`` (`r`), scheme `:scheme`:
- `"explicit"`: forward Euler in time (FTCS), stable only for ``r \\le 1/2``; above, round-off errors in the
  shortest wave grow by ``|1 - 4r|`` per step and take over;
- `"implicit"`: backward Euler, stable for every `r`, first order in time;
- `"crank_nicolson"`: the average of both, stable and second order in time.
"""
function solve_heat_1d(params::ParamDict)
    N, κ, T, r = params[:N], params[:kappa], params[:T], params[:r]
    scheme = params[:scheme]
    dx = 1.0 / N
    x = collect(range(0.0, 1.0, length = N + 1))
    t, dt = _time_grid(T, r * dx^2 / κ)
    ρ = κ * dt / dx^2

    # θ-scheme on the interior points: (I - θρL) vⁿ⁺¹ = (I + (1-θ)ρL) vⁿ, L = tridiag(1, -2, 1)
    θ = scheme == "explicit" ? 0.0 : scheme == "implicit" ? 1.0 : scheme == "crank_nicolson" ? 0.5 :
        throw(ArgumentError("unknown scheme $(repr(scheme))"))
    m = N - 1
    A = lu(Tridiagonal(fill(-θ * ρ, m - 1), fill(1 + 2θ * ρ, m), fill(-θ * ρ, m - 1)))

    u = zeros(SVector{1, Float64}, N + 1, length(t))
    v = sin.(π .* x) .+ sin.(3π .* x) ./ 2
    v[1] = v[end] = 0.0
    rhs = zeros(m)
    u[:, 1] .= SVector.(v)
    for n in 1:(length(t) - 1)
        for i in 2:N
            rhs[i - 1] = v[i] + (1 - θ) * ρ * (v[i - 1] - 2v[i] + v[i + 1])
        end
        θ == 0 ? (v[2:N] .= rhs) : (v[2:N] .= A \ rhs)
        u[:, n + 1] .= SVector.(v)
    end
    return create_sim_data(x, u, t, params)
end

"""
    exact_heat_1d(params)

The exact solution of [`solve_heat_1d`](@ref): each sine mode decays with ``e^{-\\kappa k^2 \\pi^2 t}``.
"""
function exact_heat_1d(params::ParamDict)
    κ = params[:kappa]
    return xt -> SVector(exp(-κ * π^2 * xt[2]) * sin(π * xt[1]) + exp(-9κ * π^2 * xt[2]) * sin(3π * xt[1]) / 2)
end

"""
    test_heat_1d() -> SimulationConfig

Diffusion of two sine modes ([`solve_heat_1d`](@ref)) with an explicit, an implicit and the Crank–Nicolson scheme and
the exact solution, swept over the diffusion number `r`: at `r = 0.6` the explicit scheme is unstable.
"""
function test_heat_1d()
    shared = create_param_dict(:N => 50, :kappa => 1.0, :T => 0.1, :r => 0.4, :sim_func_name => :solve_heat_1d)
    methods = create_method_dict(:exact => create_param_dict(),
                                 :explicit => create_param_dict(:scheme => "explicit"),
                                 :implicit => create_param_dict(:scheme => "implicit"),
                                 :crank_nicolson => create_param_dict(:scheme => "crank_nicolson"))
    varied = create_varied_dict(:r => [0.25, 0.4, 0.5, 0.6])
    return SimulationConfig(shared, methods, [:exact, :explicit, :implicit, :crank_nicolson];
                            varied = varied, reference = :exact_heat_1d)
end
