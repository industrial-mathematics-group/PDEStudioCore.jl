using PDEStudioCore, JLD2, StaticArrays, Logging

reference_cache_solver(p) = create_sim_data([0.0, 1.0], [1.0, 1.0], p)

function check_reference_cache()
    mktempdir() do root
        set_save_path!(joinpath(root, "results"))
        set_stat_preset!("hyperbolic")
        set_stat_registry!(Dict(:l1error => :time))
        reference_file = joinpath(root, "reference.jl")
        write_reference(value) = write(reference_file, "reference_cache_factory(p) = _ -> $value\n")
        config = SimulationConfig(create_param_dict(:sim_func_name => :reference_cache_solver);
                                  reference = :reference_cache_factory)
        params = only(generate_tasks(config))

        function run(label; on_changed_sources = :warn)
            Base.include(Main, reference_file)
            summary = Base.invokelatest(run_all_simulations, config;
                                        calculate_stats = true, on_changed_sources)
            data = load_sim_data(params)
            record = jldopen(file -> file["evaluated_reference"], get_file_name(params), "r")
            l2 = haskey(data.stats, :l2error) ? only(data.stats[:l2error]) : missing
            println(label, " stats=", only(keys(summary.stats)), " L1=", only(data.stats[:l1error]),
                    " L2=", l2, " record=", record)
        end

        write_reference(2.0)
        run("A initial")
        write_reference(4.0)
        register_stat!(:l2error, :time)
        run("B plus L2")
        write_reference(2.0)
        run("A restored"; on_changed_sources = :recompute)
        println("Expected after restoring A: L1=2.0 L2=", sqrt(2.0))
    end
end

module ΔReview
struct UnicodeTag end
end

function check_type_name()
    p = create_param_dict(:tag => ΔReview.UnicodeTag)
    println("Before importing UnicodeTag: text=", val2str(ΔReview.UnicodeTag), " hash=", calculate_hash(p))
    Base.eval(Main, :(using .ΔReview: UnicodeTag))
    println("After importing UnicodeTag: text=",
            Base.invokelatest(val2str, ΔReview.UnicodeTag),
            " hash=", Base.invokelatest(calculate_hash, p))
end

function check_float32_scatter()
    particles = create_sim_data([SVector(0.0f0)], [1.0f30], ParamDict())
    grid = convert_to_eulerian(particles, (1,))
    println("Float32 one-particle scatter: input=", only(only(only(particles.u))),
            " output=", only(only(grid.u)))
end

with_logger(NullLogger()) do
    check_reference_cache()
    check_type_name()
    check_float32_scatter()
end
