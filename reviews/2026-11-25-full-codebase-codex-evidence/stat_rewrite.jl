using PDEStudioCore, Logging

Logging.disable_logging(Logging.Warn)
rewrite_solver(p) = create_sim_data([0., 1.], ones(2), p)
rewrite_ref_a(p) = _ -> 2.0
rewrite_ref_b(p) = _ -> 4.0
set_stat_preset!("hyperbolic")

function run_case(edit_note)
    mktempdir() do root
        set_save_path!(root)
        set_stat_registry!(Dict(:l1error => :time))
        p = create_param_dict(:sim_func_name => :rewrite_solver)
        c = SimulationConfig(p; reference = :rewrite_ref_a)
        run_all_simulations(c; calculate_stats = true)
        d = load_sim_data(p)
        println("L1 under reference A: ", d.stats[:l1error][1])
        if edit_note
            d.metadata[:note] = "checked"
            save_sim_data(d; overwrite = true, verbose = false)
            path = get_file_name(p)
            evidence = PDEStudioCore.JLD2.jldopen(path, "r") do file
                (haskey(file, "evaluated_stats"), haskey(file, "evaluated_reference"))
            end
            println("After metadata edit: (has evaluated stats, has evaluated reference)=", evidence)
        end
        c.reference = :rewrite_ref_b
        set_stat_registry!(Dict(:l2error => :time))
        result = run_all_simulations(c; calculate_stats = true)
        d = load_sim_data(p)
        println("Switch to B with only L2 registered: ", result.stats,
                " L1 kept=", haskey(d.stats, :l1error), " L2=", d.stats[:l2error][1])
        register_stat!(:l1error, :time)
        result = run_all_simulations(c; calculate_stats = true)
        println("Re-register L1: ", result.stats, " L1=", load_sim_data(p).stats[:l1error][1])
        run_all_simulations(c; calculate_stats = true, force_stats = true)
        println("Forced L1 under reference B: ", load_sim_data(p).stats[:l1error][1])
    end
end

for edit_note in (false, true)
    println("Metadata edit=", edit_note)
    run_case(edit_note)
end
