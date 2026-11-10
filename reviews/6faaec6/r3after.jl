using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
set_save_path!(ARGS[1])
PDEStudioCore.set_target_module!(@__MODULE__)
include(joinpath(@__DIR__, "solver_mx.jl"))
p = Dict{Symbol,Any}(:case => :mx, :sim_func_name => :solvermx)
path = get_file_name(p)
JLD2.jldopen(path, "r") do f; println(sort(collect(keys(f)))); println("format ", PDEStudioCore._format_version(f)); end
d = load_sim_data(p); println(typeof(d), " ", d.metadata)
cfg = SimulationConfig(p; postprocess = :markpost)
s = run_all_simulations(cfg; load_sources = false); println(s.postprocessing)
println(Dict(k => length(v) for (k, v) in upgrade_sim_data()))
