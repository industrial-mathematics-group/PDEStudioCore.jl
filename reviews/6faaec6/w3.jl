using PDEStudioCore, StaticArrays
set_save_path!(ARGS[1])
PDEStudioCore.set_target_module!(@__MODULE__)
include(joinpath(@__DIR__, "solver_mx.jl"))
cfg = SimulationConfig(Dict{Symbol,Any}(:case => :mx, :sim_func_name => :solvermx); postprocess = :markpost)
s = run_all_simulations(cfg; calculate_stats = true, load_sources = false)
println((length(s.ran), s.postprocessing))
println(load_sim_data(generate_tasks(cfg)[1]).metadata)
