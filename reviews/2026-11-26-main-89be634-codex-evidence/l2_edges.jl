using PDEStudioCore, Logging
using PDEStudioCore.StaticArrays: SVector
Logging.disable_logging(Logging.Error)
set_stat_preset!("hyperbolic")
set_stat_registry!(Dict(:l2norm => Symbol[], :l2error => Symbol[]))
grid = [0., 1.]

d = create_sim_data(grid, [SVector(0., 1.), SVector(NaN, 2.)], ParamDict())
calculate_all_stats!(d; save = false)
println("L2 of [0, NaN] in the first component: ", d.stats[:l2norm])

d = create_sim_data(grid, [1., 1.], ParamDict())
calculate_all_stats!(d, x -> iszero(x[1]) ? 1.0 : NaN; save = false)
println("L2 error with a partly undefined, otherwise exact reference: ",
        haskey(d.stats, :l2error) ? string(d.stats[:l2error]) : "omitted (all NaN)")

set_stat_registry!(Dict(:l2norm => Symbol[]))
axes = ([0., 2e-162], [0., 2e-162], [0., 1e308])
u = ones(2, 2, 2)
d = create_sim_data(axes, u, ParamDict())
calculate_all_stats!(d; save = false)
measure = prod(BigFloat(x) for x in d.domain.spacing)
expected = Float64(sqrt(length(u) * measure))
println("Normal final measure after an underflowing intermediate: reported=", only(d.stats[:l2norm]),
        " expected=", expected, " ratio=", only(d.stats[:l2norm]) / expected)
