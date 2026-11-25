using PDEStudioCore
using PDEStudioCore.StaticArrays: SVector

x = floatmax(Float64) / 2
data = create_sim_data([0., 1., 2.], fill(x, 3), ParamDict())
println("Float64 finite constant field=", x, " max=", only(check_data(data).C1_Max),
        " reported mean=", only(check_data(data).C1_Mean), " expected mean=", x)

set_stat_preset!("hyperbolic")
set_stat_registry!(Dict(:l2norm => Symbol[]))
data = create_sim_data([0.0, 1e-200], [1e200, 1e200], ParamDict())
calculate_all_stats!(data; save = false)
println("Scaled Float64 L2 reported=", only(data.stats[:l2norm]),
        " expected=", Float64(sqrt(big(2) * big"1e-200") * big"1e200"))
