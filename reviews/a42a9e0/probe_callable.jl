# A solver / post-processor that is a callable object (resolved by name like any global)
include(joinpath(@__DIR__, "common.jl"))
struct LinSolver; scale::Float64; end
(s::LinSolver)(params) = lin_solver(params)
const callable_solver = LinSolver(1.0)
struct Post end
(::Post)(d) = nothing
const callable_post = Post()
println("nameof works on the object: ", applicable(nameof, callable_solver))
cfg = SimulationConfig(Dict(:sim_func_name => :callable_solver, :n => 4))
s = run_all_simulations(cfg)
println("solver as callable object: ran=", length(s.ran), " failed=", s.failed)
cfg2 = SimulationConfig(Dict(:sim_func_name => :lin_solver, :n => 5); postprocess = :callable_post)
try
    s2 = with_logger(NullLogger()) do; run_all_simulations(cfg2); end
    println("post-processor as callable object: post=", s2.postprocessing)
catch e
    println("post-processor as callable object: run_all_simulations threw ", sprint(showerror, e)[1:min(end, 150)])
end
