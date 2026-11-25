using PDEStudioCore, Logging
using PDEStudioCore.StaticArrays: SVector
Logging.disable_logging(Logging.Error)
mode = first(ARGS)

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

if mode in ("prepare", "check")
    set_save_path!(ARGS[2])
    p = create_param_dict(:sim_func_name => :ownership_solver)
    c = SimulationConfig(p; postprocess = :ownership_post)
    if mode == "prepare"
        run_all_simulations(c)
        d = load_sim_data(p)
        println("0.9 store: calibration=", first(d.stats[:calibration]), " quality=", first(d.stats[:quality]))
    else
        d = load_sim_data(p)
        println("Before callback: calibration layer=", stat_layer(d, :calibration))
        r = run_all_simulations(c; force_postprocess = true)
        d = load_sim_data(p)
        println("After callback: ", r.postprocessing, " calibration=", first(d.stats[:calibration]),
                " layer=", stat_layer(d, :calibration), " owned=", d.metadata[:postprocessed][:ownership_post][:keys])
        set_stat_registry!(Dict(:maintenance => Symbol[]))
        r = run_all_simulations(c; calculate_stats = true, post_process = false)
        d = load_sim_data(p)
        println("After statistics refresh: ", r.stats, " has solver calibration=", haskey(d.stats, :calibration))
    end
elseif mode == "assign"
    function prior_post(d)
        add_stat!(d, :first_post, 10.0, Symbol[])
        return true
    end
    function assigned_post(d)
        d.stats = merge(copy(d.stats), Dict(:second_post => SVector(20.0)))
        return true
    end
    mktempdir() do root
        set_save_path!(root)
        p = create_param_dict(:sim_func_name => :ownership_solver)
        c = SimulationConfig(p; postprocess = :prior_post)
        run_all_simulations(c)
        println("After first callback: ", sort!(collect(keys(load_sim_data(p).stats))))
        c.postprocess = :assigned_post
        r = run_all_simulations(c)
        d = load_sim_data(p)
        println("After whole-dictionary assignment: ", r.postprocessing, " stats=", sort!(collect(keys(d.stats))),
                " second layer=", stat_layer(d, :second_post), " owned=", d.metadata[:postprocessed][:assigned_post][:keys])
    end
end
