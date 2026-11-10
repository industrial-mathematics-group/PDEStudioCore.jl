# sim_data_table: parameters named like a fixed column; version-0 files
include(joinpath(@__DIR__, "common.jl"))
cfg = SimulationConfig(Dict(:sim_func_name => :lin_solver, :n => 4, :solver => "rk4", :kind => "test", :file => "mesh.msh"))
with_logger(NullLogger()) do; run_all_simulations(cfg); end
t = sim_data_table()
println("columns: ", names(t))
println("solver column = ", repr(t.solver[1]), " (provenance solver is lin_solver; parameter solver = rk4)")
println("kind column = ", repr(t.kind[1]), "  file column = ", repr(t.file[1]))
# version-0 file (only the data): appears?
q = create_param_dict(:n => 6); d = lin_solver(q)
f = joinpath(get_save_path(), "data", "2020-01-01_00-00-00_000_" * PDEStudioCore._param_hash(q) * ".jld2")
JLD2.jldopen(io -> (io["raw"] = d), f, "w")
println("rows with a version-0 file present: ", size(sim_data_table(), 1), " (2 stored runs)")
