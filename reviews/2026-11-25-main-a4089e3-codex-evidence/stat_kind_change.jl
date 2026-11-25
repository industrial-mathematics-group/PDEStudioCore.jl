using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)

function scalar_solver(p)
    d = create_sim_data([0., 1.], ones(2), p)
    add_stat!(d, :calibration, 47.0, Symbol[])
    return d
end
function vector_post(d)
    d.stats[:calibration] = [47.0]
    return true
end
mktempdir() do root
    set_save_path!(root)
    p = create_param_dict(:sim_func_name => :scalar_solver)
    run_all_simulations(SimulationConfig(p))
    println("Before callback: ", typeof(load_sim_data(p).stats[:calibration]))
    r = run_all_simulations(SimulationConfig(p; postprocess = :vector_post))
    d = load_sim_data(p)
    println("After callback: ", r.postprocessing, " type=", typeof(d.stats[:calibration]),
            " kept=", get_kept_dims(:calibration, d.domain), " layer=", stat_layer(d, :calibration))
end
