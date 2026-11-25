using PDEStudioCore, Logging
Logging.disable_logging(Logging.Warn)
const INCLUDE_COUNT = Ref(0)
alias_solver(p) = create_sim_data([0.0], [Float64(INCLUDE_COUNT[])], p)

mktempdir() do root
    set_save_path!(joinpath(root, "runs"))
    a, b = joinpath.(Ref(root), ("a.jl", "b.jl"))
    for (tag, file, other, value) in ((:a, a, b, 10), (:b, b, a, 20))
        write(file, """
        switchable_solver(p) = create_sim_data([0.0, 1.0], [$(value).0, $(value).0], p)
        function config_$(tag)()
            p = create_param_dict(:sim_func_name => :switchable_solver)
            return SimulationConfig(p; sources = [$(repr(other)), @__FILE__])
        end
        config_$(tag)
        """)
    end
    parent_config = Base.include(Main, b)
    first = Base.invokelatest(parent_config)
    original = run_all_simulations(first; on_changed_sources = :recompute)
    parameters = only(original.tasks)
    println("Root b with helper a: ran=", length(original.ran), " field=", load_sim_data(parameters).u[1][1])

    other_config = Base.include(Main, a)
    second = Base.invokelatest(other_config)
    r = run_all_simulations(second; on_changed_sources = :recompute)
    println("Root a with helper b: ran=", length(r.ran), " cached=", length(r.cached),
            " changed=", length(r.changed), " field=", load_sim_data(parameters).u[1][1])

    run_all_simulations(second; force_overwrite = true)
    println("Root a forced: field=", load_sim_data(parameters).u[1][1])
end

if Sys.isunix()
    mktempdir() do root
        set_save_path!(joinpath(root, "runs"))
        source = joinpath(root, "source.jl")
        alias = joinpath(root, "alias.jl")
        write(source, "INCLUDE_COUNT[] += 1\n")
        symlink(source, alias)
        parameters = create_param_dict(:sim_func_name => :alias_solver)
        for paths in ([source, source], [source, alias])
            try
                r = run_all_simulations(SimulationConfig(parameters; sources = paths); force_overwrite = true)
                println("Duplicate ", basename.(paths), ": ran=", length(r.ran), " includes=", INCLUDE_COUNT[])
            catch e
                e isa ArgumentError || rethrow()
                println("Duplicate ", basename.(paths), ": rejected; includes=", INCLUDE_COUNT[])
            end
        end
    end
end
