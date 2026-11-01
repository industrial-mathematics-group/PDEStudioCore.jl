"""
    solve_poisson_2d(params) -> ESimData

The Poisson equation ``-\\Delta u = 2\\pi^2 \\sin(\\pi x)\\sin(\\pi y)`` on the unit square with ``u = 0`` on the
boundary (solution ``\\sin(\\pi x)\\sin(\\pi y)``), five-point Laplacian on `N` intervals per direction, solved
iteratively from ``u = 0`` with `iterations` sweeps of the method `:solver`:
- `"jacobi"`: every point from the old values of its neighbours; slow (``\\approx N^2`` sweeps per digit);
- `"gauss_seidel"`: uses the new values as soon as they exist; about twice as fast;
- `"sor"`: Gauss–Seidel over-relaxed with the optimal ``\\omega = 2 / (1 + \\sin(\\pi / N))``; ``\\approx N`` sweeps.

A stationary problem: the time axis `t` counts the iterations (``t = k`` after ``k`` sweeps), so the plots show the
convergence. The error statistics level off at the discretisation error ``O(1/N^2)``. (It is called `t` rather than
e.g. `:iteration` so that frontends that know the axes `x, y, z, t`, such as PDEStudio, show it as it is.)
"""
function solve_poisson_2d(params::ParamDict)
    N, iterations, solver = params[:N], params[:iterations], params[:solver]
    solver in ("jacobi", "gauss_seidel", "sor") || throw(ArgumentError("unknown solver $(repr(solver))"))
    h = 1.0 / N
    x = collect(range(0.0, 1.0, length = N + 1))
    f = [2π^2 * sin(π * xi) * sin(π * yj) for xi in x, yj in x]
    ω = solver == "sor" ? 2 / (1 + sin(π * h)) : 1.0

    v = zeros(N + 1, N + 1)
    w = copy(v)
    u = zeros(SVector{1, Float64}, N + 1, N + 1, iterations + 1)
    for k in 1:iterations
        if solver == "jacobi"
            for j in 2:N, i in 2:N
                w[i, j] = (v[i - 1, j] + v[i + 1, j] + v[i, j - 1] + v[i, j + 1] + h^2 * f[i, j]) / 4
            end
            v, w = w, v
        else
            for j in 2:N, i in 2:N                     # in place: new neighbour values are used at once
                gs = (v[i - 1, j] + v[i + 1, j] + v[i, j - 1] + v[i, j + 1] + h^2 * f[i, j]) / 4
                v[i, j] += ω * (gs - v[i, j])
            end
        end
        u[:, :, k + 1] .= SVector.(v)
    end
    return create_sim_data((x, x), u, collect(0.0:iterations), params)   # dims (:x, :y, :t), t = iterations
end

"""
    exact_poisson_2d(params)

The exact solution of [`solve_poisson_2d`](@ref) (the same for every iteration).
"""
exact_poisson_2d(params::ParamDict) = xyt -> SVector(sin(π * xyt[1]) * sin(π * xyt[2]))

"""
    test_poisson_2d() -> SimulationConfig

The convergence of three iterative solvers for the Poisson equation ([`solve_poisson_2d`](@ref)), with the exact
solution, swept over the grid size: Jacobi and Gauss–Seidel slow down with ``N^2``, SOR only with ``N``.
"""
function test_poisson_2d()
    shared = create_param_dict(:N => 32, :iterations => 200, :sim_func_name => :solve_poisson_2d)
    methods = create_method_dict(:exact => create_param_dict(),
                                 :jacobi => create_param_dict(:solver => "jacobi"),
                                 :gauss_seidel => create_param_dict(:solver => "gauss_seidel"),
                                 :sor => create_param_dict(:solver => "sor"))
    varied = create_varied_dict(:N => [16, 32])
    return SimulationConfig(shared, methods, [:exact, :jacobi, :gauss_seidel, :sor];
                            varied = varied, reference = :exact_poisson_2d)
end
