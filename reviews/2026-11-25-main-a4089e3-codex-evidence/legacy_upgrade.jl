using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)
action, root = ARGS
set_save_path!(root)
legacy_solver(p) = create_sim_data([0., 1.], [1., 1.], p)
legacy_reference_b(p) = _ -> 4.0
p = create_param_dict(:sim_func_name => :legacy_solver)

d = load_sim_data(p)
if action == "resave"
    println("Initial 0.10, no preset: mass layer=", stat_layer(d, :mass))
    d.metadata[:note] = "checked"
    save_sim_data(d; overwrite = true, verbose = false)
    println("Initial 0.10 resave kept mass=", haskey(load_sim_data(p).stats, :mass))
elseif action == "refresh"
    set_stat_preset!("hyperbolic")
    println("Before refresh: mass layer=", stat_layer(load_sim_data(p), :mass))
    set_stat_registry!(Dict(:l1error => :time))
    s = run_all_simulations(SimulationConfig(p; reference = :legacy_reference_b); calculate_stats = true)
    println("After refresh: ", s.stats, " mass present=", haskey(load_sim_data(p).stats, :mass))
end
