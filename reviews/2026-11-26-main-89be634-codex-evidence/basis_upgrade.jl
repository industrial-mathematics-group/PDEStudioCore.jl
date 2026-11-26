using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)
action, root = ARGS
set_save_path!(root)
callback(d) = (d.metadata[:invocations] = get(d.metadata, :invocations, 0) + 1; true)
function solver(p)
    d = create_sim_data([0., 1.], ones(2), p)
    add_stat!(d, :weight, 2.0, Symbol[])
    return d
end
p = create_param_dict(:sim_func_name => :solver)
c = SimulationConfig(p; postprocess = :callback)

if action == "prepare"
    run_all_simulations(c)
end
function report(label, result)
    d = load_sim_data(p)
    println(label, ": ", result.postprocessing, " invocations=", d.metadata[:invocations])
end
report("Before metadata save", run_all_simulations(c))
d = load_sim_data(p)
d.metadata[:note] = "reviewed"
save_sim_data(d; overwrite = true, verbose = false)
report("After metadata save", run_all_simulations(c))
