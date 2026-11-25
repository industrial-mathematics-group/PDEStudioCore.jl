using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)
action, root = ARGS
set_save_path!(root)

legacy_solver(p) = create_sim_data([0., 1.], [1., 1.], p)
legacy_reference_a(p) = _ -> 2.0
legacy_reference_b(p) = _ -> 4.0
p = create_param_dict(:sim_func_name => :legacy_solver)

if action == "prepare"
    set_stat_preset!("hyperbolic")
    set_stat_registry!(Dict(:mass => :time, :l1error => :time))
    c = SimulationConfig(p; reference = :legacy_reference_a)
    s = run_all_simulations(c; calculate_stats = true)
    d = load_sim_data(p)
    println("Stored 0.9: ", s.stats, " stats=", sort!(collect(keys(d.stats))))
elseif action == "check"
    d = load_sim_data(p)
    println("Fresh 0.10 before loading preset: mass layer=", stat_layer(d, :mass))
    set_stat_preset!("hyperbolic")
    d = load_sim_data(p)
    println("After loading preset: mass layer=", stat_layer(d, :mass))
    set_stat_registry!(Dict(:l1error => :time))
    c = SimulationConfig(p; reference = :legacy_reference_b)
    s = run_all_simulations(c; calculate_stats = true)
    println("After changing reference with preset installed: ", s.stats, " keys=", sort!(collect(keys(load_sim_data(p).stats))))
elseif action == "check_without_preset"
    d = load_sim_data(p)
    println("Before reference change, no preset: mass layer=", stat_layer(d, :mass))
    PDEStudioCore.calc_stat(::Val{:l1error}, coords, u, ana, domain) = sum(abs(first(v) - first(a)) for (v, a) in zip(u, ana))
    set_stat_registry!(Dict(:l1error => :time))
    c = SimulationConfig(p; reference = :legacy_reference_b)
    s = run_all_simulations(c; calculate_stats = true)
    println("After changing reference without preset: ", s.stats, " keys=", sort!(collect(keys(load_sim_data(p).stats))))
end
