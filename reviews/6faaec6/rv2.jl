using PDEStudioCore, StaticArrays
set_save_path!(ARGS[1])
PDEStudioCore.set_target_module!(@__MODULE__)
include(joinpath(@__DIR__, "solver_mx.jl"))
noop2(d) = nothing
cfg = SimulationConfig(Dict{Symbol,Any}(:case => :v2, :sim_func_name => :solvermx); postprocess = :noop2)
s = run_all_simulations(cfg; load_sources = false); println(s.postprocessing)
t = sim_data_table(); println((t.format_version, t.solver, t.wall_time, t.postprocessed))
println(load_sim_data(generate_tasks(cfg)[1]).metadata)
