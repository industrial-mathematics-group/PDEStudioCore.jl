using PDEStudioCore, Logging
Logging.disable_logging(Logging.Warn)

mode, root = ARGS
set_save_path!(joinpath(root, "runs"))
file = joinpath(root, "config.jl")
if mode == "prepare"
    write(file, """
    source_meta_solver(p) = create_sim_data([0.0], [2.0], p; metadata = Dict(:configuration_source => "calibration record 47"))
    SimulationConfig(create_param_dict(:sim_func_name => :source_meta_solver); sources = [@__FILE__])
    """)
end
config = Base.include(Main, file)
s = run_all_simulations(config; on_changed_sources = :recompute)
d = load_sim_data(only(s.tasks))
println(mode, ": changed=", length(s.changed), " ran=", length(s.ran), " cached=", length(s.cached),
        " configuration_source=", d.metadata[:configuration_source])
