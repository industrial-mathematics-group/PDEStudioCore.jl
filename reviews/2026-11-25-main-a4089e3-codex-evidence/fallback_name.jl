using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)
PDEStudioCore.calc_stat(::Val{:__no_statistic__}, coords, u, ana, domain) = first(u)
solver(p) = create_sim_data([0., 1.], ones(2), p)
reference(p) = _ -> 2.0
mktempdir() do root
    set_save_path!(root)
    p = create_param_dict(:sim_func_name => :solver)
    c = SimulationConfig(p; reference = :reference)
    set_stat_registry!(Dict(:__no_statistic__ => Symbol[]))
    r = run_all_simulations(c; calculate_stats = true)
    println("A registered reference statistic implemented under the allowed name: ", r.stats, " failures=", last.(r.stats_failed))
    set_stat_registry!(Dict(:spelled_wrong => Symbol[]))
    c.reference = nothing
    r = run_all_simulations(c; calculate_stats = true)
    println("A different registered name with no implementation: ", r.stats, " failures=", last.(r.stats_failed))
end
