using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)

function edit_solver(p)
    data = create_sim_data([0., 1.], ones(2), p)
    add_stat!(data, :weights, [2., 3.], :x)
    return data
end
function edit_post(d)
    total = haskey(d.stats, :weights) ? sum(first, d.stats[:weights]) : -1.0
    add_stat!(d, :weighted_total, total, Symbol[])
    return true
end

for edit in (:replace, :remove)
    mktempdir() do root
        set_save_path!(root)
        reset_stat_registry!()
        p = create_param_dict(:sim_func_name => :edit_solver)
        c = SimulationConfig(p; postprocess = :edit_post)
        run_all_simulations(c; calculate_stats = true)
        d = load_sim_data(p)
        println(edit, " initial post=", first(d.stats[:weighted_total]))
        if edit === :replace
            add_stat!(d, :weights, [10., 20.], :x)
        else
            delete_stat!(d, :weights)
        end
        save_sim_data(d; overwrite = true, verbose = false)
        r = run_all_simulations(c; calculate_stats = true)
        println(edit, " after save: ", r.postprocessing, " post=", first(load_sim_data(p).stats[:weighted_total]))
        r = run_all_simulations(c; calculate_stats = true, force_postprocess = true)
        println(edit, " forced: ", r.postprocessing, " post=", first(load_sim_data(p).stats[:weighted_total]))
    end
end
