using PDEStudioCore, Logging
Logging.disable_logging(Logging.Warn)
set_stat_preset!("hyperbolic")

stats_solver(p) = create_sim_data([0., 1.], ones(2), p)
reference_a(p) = _ -> 2.0
reference_b(p) = _ -> 4.0

function report(label, config, p)
    result = run_all_simulations(config; calculate_stats = true)
    d = load_sim_data(p)
    l1 = haskey(d.stats, :l1error) ? only(d.stats[:l1error]) : missing
    l2 = haskey(d.stats, :l2error) ? only(d.stats[:l2error]) : missing
    names = PDEStudioCore.JLD2.jldopen(f -> f["evaluated_stats"], get_file_name(p), "r")
    println(label, ": ", result.stats, " L1=", l1, " L2=", l2, " record=", names)
end

mktempdir() do root
    set_save_path!(root)
    p = create_param_dict(:sim_func_name => :stats_solver)
    c = SimulationConfig(p; reference = :reference_a)
    set_stat_registry!(Dict(:l1error => :time))
    report("Reference A, L1 registered", c, p)
    set_stat_registry!(Dict(:l2error => :time))
    report("Reference A, L2 registered", c, p)
    c.reference = :reference_b
    report("Reference B, L2 registered", c, p)
    register_stat!(:l1error, :time)
    report("Reference B, L1 re-registered", c, p)
    s = run_all_simulations(c; calculate_stats = true, force_stats = true)
    println("Forced: ", s.stats, " L1=", only(load_sim_data(p).stats[:l1error]))
end
