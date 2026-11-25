using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)

d = create_sim_data([0., 1.], [1., 1.], ParamDict())
returned = calculate_all_stats!(d; save = false)
println("calculate_all_stats! returns ", typeof(returned), " same dataset=", returned === d)

solver_without_stats(p) = create_sim_data([0., 1.], [1., 1.], p)
mktempdir() do root
    set_save_path!(root)
    set_stat_registry!(Dict(:typo_without_method => Symbol[]))
    p = create_param_dict(:sim_func_name => :solver_without_stats)
    c = SimulationConfig(p)
    result = run_all_simulations(c; calculate_stats = true)
    println("Registered name without a method or reference: ", result.stats,
            " failed=", length(result.stats_failed), " present=", haskey(load_sim_data(p).stats, :typo_without_method))
end
