# 0.4 on a v3 file
using PDEStudioCore, StaticArrays
set_save_path!(ARGS[1])
PDEStudioCore.set_target_module!(@__MODULE__)
include(joinpath(@__DIR__, "solver_mx.jl"))
p = Dict{Symbol,Any}(:case => :mx, :sim_func_name => :solvermx)
t(label, f) = try println("OK   ", label, " => ", f()) catch e; println("FAIL ", label, " => ", first(sprint(showerror, e), 300)) end
t("exists", () -> does_sim_data_exist(p))
t("load", () -> (d = load_sim_data(p); (typeof(d), d isa AbstractSimData)))
t("conv_L", () -> typeof(load_sim_data(p, :lagrangian)))
t("pipeline stats", () -> (s = run_all_simulations(SimulationConfig(p); calculate_stats = true); s))
if length(ARGS) > 1
    p2 = copy(p); p2[:scale] = 1.0   # same hash? no: different params; use force_overwrite on the same params
    t("force_overwrite", () -> (s = run_all_simulations(SimulationConfig(p); force_overwrite = true); length(s.ran)))
end
