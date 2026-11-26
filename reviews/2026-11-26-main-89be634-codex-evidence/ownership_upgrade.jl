using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)
action, root = ARGS
set_save_path!(root)
function ownership_solver(p)
    d = create_sim_data([0., 1.], [1., 1.], p)
    add_stat!(d, :calibration, 47.0, Symbol[])
    return d
end
function ownership_post(d)
    scratch = create_sim_data([0., 1.], [0., 0.], ParamDict())
    add_stat!(scratch, :calibration, 99.0, Symbol[])
    add_stat!(d, :quality, 2.0, Symbol[])
    return true
end
PDEStudioCore.calc_stat(::Val{:maintenance}, coords, u, domain) = first(u)
p = create_param_dict(:sim_func_name => :ownership_solver)
c = SimulationConfig(p; postprocess = :ownership_post)
if action == "save_ownership"
    r = run_all_simulations(c; force_postprocess = true)
    d = load_sim_data(p)
    println("Save using #70: ", r.postprocessing, " calibration=", first(d.stats[:calibration]),
            " recorded owner keys=", d.metadata[:postprocessed][:ownership_post][:keys],
            " has basis=", haskey(d.metadata[:stat_records], :basis))
else
    d = load_sim_data(p)
    println("Before refresh: calibration=", first(d.stats[:calibration]), " layer=", stat_layer(d, :calibration))
    set_stat_registry!(Dict(:maintenance => Symbol[]))
    r = run_all_simulations(c; calculate_stats = true, post_process = false)
    d = load_sim_data(p)
    println("Current statistics refresh: ", r.stats, " has solver calibration=", haskey(d.stats, :calibration))
end
