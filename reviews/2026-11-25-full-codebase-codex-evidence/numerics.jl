using PDEStudioCore, Logging
Logging.disable_logging(Logging.Warn)
println("Julia ", VERSION, " threads=", Threads.nthreads())

axes = ([0., 2.], [0., 1., 3.], [0., 0.25, 1.])
x, y, t = axes
field = [2xi - 3yj + 10k for xi in x, yj in y, k in eachindex(t)]
dataset = create_sim_data((x, y), field, t, ParamDict())
resampled = resample_eulerian(dataset, (5, 7, 6))
newx, newy, newt = resampled.axes
expected = [2xi - 3yj + 10argmin(abs.(t .- tk)) for xi in newx, yj in newy, tk in newt]
err = maximum(abs.(first.(resampled.u) .- expected))
@assert err < 1e-12
println("Affine spatial and nearest-time interpolation max error: ", err)

mktempdir() do root
    set_save_path!(root)
    set_stat_preset!("hyperbolic")
    c = test_heat_1d()
    c.shared[:N] = 8
    c.shared[:T] = 0.01
    c.varied[:r] = [0.4]
    s = run_all_simulations(c; parallel = true, calculate_stats = true)
    @assert length(s.ran) == 3 && isempty(s.failed) && isempty(s.stats_failed)
    errors = [load_sim_data(p).stats[:l2error][end][1] for p in s.tasks]
    @assert all(isfinite, errors)
    println("Reduced heat example tasks=", length(s.ran), " final L2 errors=", errors)
end
