# Stored solver package version differs from the current one -> changed (solver in a package: PDEStudioCore.Examples)
include(joinpath(@__DIR__, "common.jl"))
cfg = test_advection_1d()
tasks = generate_tasks(cfg)
cfg1 = SimulationConfig(tasks[1])
with_logger(NullLogger()) do; run_all_simulations(cfg1); end
path = get_file_name(tasks[1])
pv = prov(path)
println("stored solver_module=", pv["solver_module"], " solver_version=", get(pv, "solver_version", nothing))
pv["solver_version"] = "0.0.1"
JLD2.jldopen(f -> (delete!(f, "provenance"); f["provenance"] = pv), path, "a+")
s = with_logger(NullLogger()) do; run_all_simulations(cfg1); end
println("after faking an older solver version: changed=", length(s.changed), " cached=", length(s.cached))
s = with_logger(NullLogger()) do; run_all_simulations(cfg1; on_changed_sources = :recompute); end
println(":recompute: ran=", length(s.ran), " new solver_version=", prov(path)["solver_version"])
# sources moved (same content, other path): not a change
src1 = joinpath(mktempdir(), "a.jl"); write(src1, "mv_solver(p) = Main.lin_solver(p)\n")
c1 = SimulationConfig(Dict(:sim_func_name => :mv_solver, :n => 4); sources = src1)
with_logger(NullLogger()) do; run_all_simulations(c1); end
src2 = joinpath(mktempdir(), "b.jl"); cp(src1, src2)
c2 = SimulationConfig(Dict(:sim_func_name => :mv_solver, :n => 4); sources = src2)
s = with_logger(NullLogger()) do; run_all_simulations(c2); end
println("moved source: changed=", length(s.changed))
# run without sources after a run with sources: not a change (only if both list sources)
c3 = SimulationConfig(Dict(:sim_func_name => :mv_solver, :n => 4))
s = with_logger(NullLogger()) do; run_all_simulations(c3); end
println("no sources now: changed=", length(s.changed))
