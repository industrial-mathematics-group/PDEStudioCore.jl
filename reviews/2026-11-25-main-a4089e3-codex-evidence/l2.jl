using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)
set_stat_preset!("hyperbolic")
set_stat_registry!(Dict(:l2norm => Symbol[]))

function l2_report(label, axes, u)
    data = create_sim_data(axes, u, ParamDict())
    calculate_all_stats!(data; save = false)
    measure = prod(BigFloat(x) for x in data.domain.spacing)
    expected = Float64(sqrt(sum(abs2(BigFloat(x)) for x in u) * measure))
    actual = only(data.stats[:l2norm])
    println(label, ": spacing=", data.domain.spacing, " reported=", actual, " expected=", expected,
            " ratio=", actual / expected)
end

l2_report("Earlier square times measure case", [0.0, 1e100], [1e149, 1e149])
l2_report("Measure overflow in two dimensions", ([0.0, 1e200], [0.0, 1e200]), fill(1e-150, 2, 2))
l2_report("Measure underflow in two dimensions", ([0.0, 1e-200], [0.0, 1e-200]), fill(1e150, 2, 2))
l2_report("Nonzero subnormal intermediate", [0.0], [sqrt(nextfloat(0.0)) * sqrt(0.51)])
