using PDEStudioCore
using PDEStudioCore.StaticArrays: SVector

set_stat_preset!("hyperbolic")
set_stat_registry!(Dict(:l2norm => Symbol[]))
grid = [0.0, 2e-300, 4e-300, 6e-300]
u = fill(1.4e-174, length(grid))
data = create_sim_data(grid, u, ParamDict())
calculate_all_stats!(data; save = false)
expected = Float64(sqrt(sum(abs2, BigFloat.(u)) * BigFloat(only(data.domain.spacing))))
println("normal measure=", only(data.domain.spacing), " reported=", only(data.stats[:l2norm]),
        " BigFloat then rounded=", expected)
@assert expected == nextfloat(0.0)

data = create_sim_data([0.0, 1.0], [SVector(0.0, 1.0), SVector(NaN, 2.0)], ParamDict())
calculate_all_stats!(data; save = false)
println("Mixed undefined norm = ", data.stats[:l2norm])

set_stat_registry!(Dict(:l2error => Symbol[]))
data = create_sim_data([0.0, 1.0], [1.0, 1.0], ParamDict())
calculate_all_stats!(data, x -> iszero(x[1]) ? 1.0 : NaN; save = false)
println("Undefined reference error = ", get(data.stats, :l2error, "omitted"))

set_stat_registry!(Dict(:relative_l2error => Symbol[]))
data = create_sim_data(grid, zeros(length(grid)), ParamDict())
calculate_all_stats!(data, _ -> first(u); save = false)
println("Relative L2 error at the same scale = ", get(data.stats, :relative_l2error, "omitted"), " expected=1.0")

set_stat_registry!(Dict(:l2norm => Symbol[]))
axes = ([0.0, 2e-162], [0.0, 2e-162], [0.0, 1e308])
data = create_sim_data(axes, ones(2, 2, 2), ParamDict())
try
    calculate_all_stats!(data; save = false)
    println("subnormal partial product returned ", data.stats[:l2norm])
catch err
    println("subnormal partial product rejected: ", sprint(showerror, err))
end
