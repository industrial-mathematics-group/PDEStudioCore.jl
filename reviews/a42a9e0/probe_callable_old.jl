# version-agnostic: does a callable-object solver / post-processor work?
include(joinpath(@__DIR__, "common.jl"))
struct LinSolver; scale::Float64; end
(s::LinSolver)(params) = lin_solver(params)
const callable_solver = LinSolver(1.0)
struct Post end
(::Post)(d) = nothing
const callable_post = Post()
with_logger(NullLogger()) do
    run_all_simulations(SimulationConfig(Dict(:sim_func_name => :callable_solver, :n => 4)))
end
println("callable solver stored its result: ", does_sim_data_exist(create_param_dict(:sim_func_name => :callable_solver, :n => 4)))
r = try with_logger(NullLogger()) do; run_all_simulations(SimulationConfig(Dict(:sim_func_name => :lin_solver, :n => 5); postprocess = :callable_post)); end; "ok" catch e; "threw " * string(typeof(e)) end
println("callable post-processor: ", r)
