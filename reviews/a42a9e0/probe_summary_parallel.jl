# RunSummary counts with parallel = true (mix of ok / failing / empty / cached tasks)
include(joinpath(@__DIR__, "common.jl"))
mixed_solver(p) = p[:n] % 7 == 0 ? error("boom $(p[:n])") : p[:n] % 5 == 0 ? NoSimData() : lin_solver(p)
cfg = SimulationConfig(Dict(:sim_func_name => :mixed_solver, :n => 3); varied = Dict(:n => collect(3:62)))
with_logger(NullLogger()) do
    run_all_simulations(SimulationConfig(Dict(:sim_func_name => :mixed_solver, :n => 3); varied = Dict(:n => collect(3:12))))
end
s = with_logger(NullLogger()) do; run_all_simulations(cfg; parallel = true); end
ns = 3:62
exp_fail = count(n -> n % 7 == 0, ns); exp_empty = count(n -> n % 7 != 0 && n % 5 == 0, ns)
exp_cached = count(n -> n <= 12 && n % 7 != 0 && n % 5 != 0, ns)
println("threads=", Threads.nthreads(), " tasks=", length(s.tasks), " ran=", length(s.ran), " cached=", length(s.cached),
        " (exp ", exp_cached, ") empty=", length(s.empty), " (exp ", exp_empty, ") failed=", length(s.failed), " (exp ", exp_fail, ")",
        " sum ok: ", length(s.ran) + length(s.cached) + length(s.empty) + length(s.failed) == 60,
        " messages ok: ", all(((p, m),) -> m == "boom $(p[:n])", s.failed))
