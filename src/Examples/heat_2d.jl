"""
    solve_heat_2d(params) -> ESimData

The heat equation ``u_t = \\kappa\\,(u_{xx} + u_{yy})`` on the unit square with ``u = 0`` on the boundary and
``u(x, y, 0) = \\sin(\\pi x)\\sin(\\pi y) + \\frac12 \\sin(2\\pi x)\\sin(3\\pi y)``, `N` intervals per direction, end time
`T` and the time step from the diffusion number ``r = \\kappa\\,\\Delta t / \\Delta x^2`` (`r`), scheme `:scheme`:
- `"explicit"`: forward Euler with the five-point Laplacian, stable only for ``r \\le 1/4``;
- `"adi"`: Peaceman–Rachford alternating direction implicit: two half steps, each implicit in one direction
  (tridiagonal solves along the lines), stable for every `r` and second order.
"""
function solve_heat_2d(params::ParamDict)
    N, κ, T, r = params[:N], params[:kappa], params[:T], params[:r]
    scheme = params[:scheme]
    scheme in ("explicit", "adi") || throw(ArgumentError("unknown scheme $(repr(scheme))"))
    dx = 1.0 / N
    x = collect(range(0.0, 1.0, length = N + 1))
    t, dt = _time_grid(T, r * dx^2 / κ)
    ρ = κ * dt / dx^2

    v = [sin(π * xi) * sin(π * yj) + sin(2π * xi) * sin(3π * yj) / 2 for xi in x, yj in x]
    v[[1, end], :] .= 0.0
    v[:, [1, end]] .= 0.0
    w = copy(v)
    m = N - 1
    A = lu(Tridiagonal(fill(-ρ / 2, m - 1), fill(1 + ρ, m), fill(-ρ / 2, m - 1)))   # I - ρ/2 L on a line
    rhs = zeros(m)

    u = zeros(SVector{1, Float64}, N + 1, N + 1, length(t))
    u[:, :, 1] .= SVector.(v)
    for n in 1:(length(t) - 1)
        if scheme == "explicit"
            for j in 2:N, i in 2:N
                w[i, j] = v[i, j] + ρ * (v[i - 1, j] + v[i + 1, j] + v[i, j - 1] + v[i, j + 1] - 4v[i, j])
            end
            v, w = w, v
        else
            for j in 2:N                               # implicit in x, explicit in y
                for i in 2:N
                    rhs[i - 1] = v[i, j] + ρ / 2 * (v[i, j - 1] - 2v[i, j] + v[i, j + 1])
                end
                w[2:N, j] .= A \ rhs
            end
            for i in 2:N                               # implicit in y, explicit in x
                for j in 2:N
                    rhs[j - 1] = w[i, j] + ρ / 2 * (w[i - 1, j] - 2w[i, j] + w[i + 1, j])
                end
                v[i, 2:N] .= A \ rhs
            end
        end
        u[:, :, n + 1] .= SVector.(v)
    end
    return create_sim_data((x, x), u, t, params)      # dims (:x, :y, :t)
end

"""
    exact_heat_2d(params)

The exact solution of [`solve_heat_2d`](@ref): the mode ``(k, l)`` decays with ``e^{-\\kappa (k^2 + l^2) \\pi^2 t}``.
"""
function exact_heat_2d(params::ParamDict)
    κ = params[:kappa]
    return xyt -> SVector(exp(-2κ * π^2 * xyt[3]) * sin(π * xyt[1]) * sin(π * xyt[2]) +
                          exp(-13κ * π^2 * xyt[3]) * sin(2π * xyt[1]) * sin(3π * xyt[2]) / 2)
end

"""
    test_heat_2d() -> SimulationConfig

Diffusion on the unit square ([`solve_heat_2d`](@ref)) with the explicit scheme, ADI and the exact solution, swept
over the diffusion number: at `r = 0.3` the explicit scheme is unstable, ADI is not.
"""
function test_heat_2d()
    shared = create_param_dict(:N => 30, :kappa => 1.0, :T => 0.05, :r => 0.2, :sim_func_name => :solve_heat_2d)
    methods = create_method_dict(:exact => create_param_dict(),
                                 :explicit => create_param_dict(:scheme => "explicit"),
                                 :adi => create_param_dict(:scheme => "adi"))
    varied = create_varied_dict(:r => [0.1, 0.25, 0.3])
    return SimulationConfig(shared, methods, [:exact, :explicit, :adi]; varied = varied, reference = :exact_heat_2d)
end
