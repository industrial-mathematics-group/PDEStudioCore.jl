using PDEStudioCore, StaticArrays
tmp = mktempdir(); cp(ARGS[1], joinpath(tmp, "s")); set_save_path!(joinpath(tmp, "s"))
PDEStudioCore.set_target_module!(@__MODULE__)
p = create_param_dict(:case => 6)
println("exists ", does_sim_data_exist(p))
s = run_all_simulations(SimulationConfig(p); calculate_stats = true)
show(stdout, MIME"text/plain"(), s); println(); println(s.failed)
