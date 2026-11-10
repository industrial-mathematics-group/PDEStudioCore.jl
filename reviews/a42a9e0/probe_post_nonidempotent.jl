# A post-processor that is not idempotent (doubles u) and returns true. Docs now say it runs "once per dataset".
include(joinpath(@__DIR__, "common.jl"))
src = joinpath(mktempdir(), "s.jl")
code = "s_solver(p) = Main.lin_solver(p)\n"
write(src, code)
const CALLS = Ref(0)
double_post(d) = (CALLS[] += 1; d.u .= d.u .* 2; true)
cfg = SimulationConfig(Dict(:sim_func_name => :s_solver, :n => 4); sources = src, postprocess = :double_post)
p = only(generate_tasks(cfg))
with_logger(NullLogger()) do
    run_all_simulations(cfg)
end
println("after 1st run: u[1] = ", load_sim_data(p).u[1], " calls=", CALLS[])
with_logger(NullLogger()) do
    run_all_simulations(cfg)
end
println("after 2nd run (same sources): u[1] = ", load_sim_data(p).u[1], " calls=", CALLS[])
write(src, code * "# comment only\n")
s = with_logger(NullLogger()) do
    run_all_simulations(cfg)   # default on_changed_sources = :warn: data kept
end
println("after comment edit (:warn keeps data): changed=", length(s.changed), " u[1] = ", load_sim_data(p).u[1], " calls=", CALLS[])
# a file written before this commit has no record: first run after the upgrade post-processes again
JLD2.jldopen(f -> delete!(f, "postprocessed"), get_file_name(p), "a+")
with_logger(NullLogger()) do
    run_all_simulations(cfg)
end
println("after removing the record (pre-commit file): u[1] = ", load_sim_data(p).u[1], " calls=", CALLS[])
