using PDEStudioCore, Logging
Logging.disable_logging(Logging.Warn)

mode, root = ARGS
set_save_path!(joinpath(root, "runs"))
a, b = joinpath.(Ref(root), ("a.jl", "b.jl"))
p = create_param_dict(:sim_func_name => :role_solver)
function report(label, result)
    d = load_sim_data(p)
    println(label, " ran=", length(result.ran), " cache=", length(result.cached), " changed=", length(result.changed),
            " field=", d.u[1][1], " tracked=", haskey(d.metadata, :configuration_source))
end
if mode == "prepare"
    for (file, helper, tag, n) in ((a, b, :a, 10), (b, a, :b, 20))
        write(file, """
        role_solver(p) = create_sim_data([0.0], [$(n).0], p)
        build_$(tag)() = SimulationConfig(create_param_dict(:sim_func_name => :role_solver); sources = [$(repr(helper)), @__FILE__])
        build_$(tag)
        """)
    end
    config = Base.invokelatest(Base.include(Main, b))
    report("Prepared B", run_all_simulations(config; on_changed_sources = :recompute))
elseif mode == "check"
    config = Base.invokelatest(Base.include(Main, a))
    report("Changed to A", run_all_simulations(config; on_changed_sources = :recompute))
    report("Forced A", run_all_simulations(config; force_overwrite = true))
end
