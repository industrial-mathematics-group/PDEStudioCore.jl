# :outdated interplay with on_changed_sources, dry_run, force_postprocess, alternating post-processors
include(joinpath(@__DIR__, "common.jl"))
src = joinpath(mktempdir(), "s.jl"); code = "o_solver(p) = Main.lin_solver(p)\n"; write(src, code)
const CALLS = Ref(0)
inc_post(d) = (CALLS[] += 1; d.u .= map(v -> v .+ 1, d.u); true)
cfg = SimulationConfig(Dict(:sim_func_name => :o_solver, :n => 4); sources = src, postprocess = :inc_post)
p = only(generate_tasks(cfg))
q(f) = with_logger(NullLogger()) do; f(); end
q(() -> run_all_simulations(cfg))
println("1st run: u=", load_sim_data(p).u[1][1], " calls=", CALLS[])
write(src, code * "# edit\n")
for mode in (:ignore, :warn)
    logs = Test.collect_test_logs() do; run_all_simulations(cfg; on_changed_sources = mode); end
    s = logs[2]; w = [l.message for l in logs[1] if l.level == Logging.Warn]
    println(rpad(mode, 8), " post=", s.postprocessing, " changed=", length(s.changed), " warnings=", length(w), " outdated-warning=", any(m -> occursin("post-processed by another version", m), w))
end
logs = Test.collect_test_logs() do; run_all_simulations(cfg; dry_run = true); end
println("dry_run  post=", logs[2].postprocessing, " outdated-warning=", any(l -> occursin("post-processed by another", l.message), logs[1]))
println("summary text: ", replace(repr("text/plain", logs[2]), "\n" => " | "))
s = q(() -> run_all_simulations(cfg; on_changed_sources = :recompute))
println(":recompute post=", s.postprocessing, " ran=", length(s.ran), " u=", load_sim_data(p).u[1][1], " calls=", CALLS[])
s = q(() -> run_all_simulations(cfg; force_postprocess = true, dry_run = true))
println("force+dry post=", s.postprocessing)
# two configs with the same tasks but different post-processors (postprocess isn't part of the hash)
const C2 = Ref(0)
other_post(d) = (C2[] += 1; nothing)
cfg2 = SimulationConfig(Dict(:sim_func_name => :o_solver, :n => 4); sources = src, postprocess = :other_post)
for i in 1:2
    q(() -> run_all_simulations(cfg2)); q(() -> run_all_simulations(cfg))
end
println("alternating cfg2/cfg x2: inc_post calls=", CALLS[], " u=", load_sim_data(p).u[1][1], " (applied ", load_sim_data(p).u[1][1] - 1, " times to the same data)")
