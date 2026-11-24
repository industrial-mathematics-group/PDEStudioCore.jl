using PDEStudioCore, Logging

review_half(p) = create_sim_data(Float16[-40000, 0, 40000], fill(Float16(0.25), 3), p)

function stored_test(mode, root)
    set_save_path!(root)
    set_stat_preset!("hyperbolic")
    set_stat_registry!(Dict(:mass => :time))
    p = create_param_dict(:sim_func_name => :review_half)
    config = SimulationConfig(p)
    function check(label; kwargs...)
        result = run_all_simulations(config; calculate_stats=true, kwargs...)
        d = load_sim_data(p)
        println(label, ": spacing=", Float64(only(d.domain.spacing)), " mass=", Float64(d.stats[:mass][1]),
                " solvers ran=", length(result.ran), " stats=", result.stats)
    end
    if mode == "seed"
        check("base creates run")
    elseif mode == "read"
        check("head normal run")
        check("head forces statistics"; force_stats=true)
        check("head reruns solver"; force_overwrite=true)
    else
        error("expected seed or read")
    end
end

with_logger(NullLogger()) do
    stored_test(ARGS...)
end
