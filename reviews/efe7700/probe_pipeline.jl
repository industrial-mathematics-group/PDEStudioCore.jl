# Probe: pipeline edge cases (post-processing, empty particle steps, tuple-suffix keys)
using Test, PDEStudioCore, StaticArrays, Logging
const JLD2 = PDEStudioCore.JLD2; const jldopen = JLD2.jldopen
global_logger(ConsoleLogger(stderr, Logging.Warn))
PDEStudioCore.set_target_module!(@__MODULE__)
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())

LOADS = Ref(0)
function tiny_solver(params)
    x = collect(range(0.0, 1.0, length = 8))
    return create_sim_data(x, [SVector(sin(xi) + ti) for xi in x, ti in (0.0, 0.5)], [0.0, 0.5], params)
end
keep_post(data) = (LOADS[] += 1; true)      # "return true to save"
reject_post(data) = false

@testset "postprocess returning false does not prevent saving" begin
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :tiny_solver, :tag => "reject"); postprocess = :reject_post)
    run_all_simulations(cfg)
    @test does_sim_data_exist(only(generate_tasks(cfg)))   # README: "a function data -> Bool deciding whether a result is saved"
end

@testset "postprocess returning true: evaluated_stats dropped, file rewritten on every run" begin
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :tiny_solver, :tag => "keep"); postprocess = :keep_post)
    run_all_simulations(cfg; calculate_stats = true)       # no reference: error stats are dropped (all NaN)
    p = only(generate_tasks(cfg)); f = get_file_name(p)
    has_eval = jldopen(fh -> haskey(fh, "evaluated_stats"), f, "r")
    @show has_eval
    @test !has_eval
    st = mtime(f); sleep(0.05)
    @test PDEStudioCore._needs_stats(f, sort!([k for k in keys(get_stat_registry()) if k !== :Solution]), false)
    run_all_simulations(cfg; calculate_stats = true)
    @test mtime(f) != st          # a cached run rewrites the file again (stats reloaded + recomputed, then post-saved)
end

@testset "wave_height on a Lagrangian step without particles" begin
    x = [[SVector(0.0), SVector(1.0)], SVector{1, Float64}[]]
    u = [[SVector(1.0), SVector(2.0)], SVector{1, Float64}[]]
    l = create_sim_data(x, u, [0.0, 1.0], create_param_dict(:tag => "empty-step"))
    err = try calculate_all_stats!(l; save = false); nothing catch e; e end
    @show typeof(err)
    @test err !== nothing     # one empty step makes the whole statistics pass throw
end

@testset "tuple suffixes" begin
    # `__all` / `__x` on a scalar parameter: obscure MethodError from deep inside generate_method_tasks
    @test_throws MethodError generate_method_tasks(create_param_dict(:N => 10), [:N__all], [[20]])
    cfg = SimulationConfig(create_param_dict(:N => 10, :sim_func_name => :tiny_solver); varied = create_varied_dict(:N__x => [20]))
    @test_throws MethodError generate_tasks(cfg)   # run_all_simulations aborts before any task
    # a vector parameter becomes a tuple
    tasks, _ = generate_method_tasks(create_param_dict(:Ns => [10, 10]), [:Ns__x], [[20]])
    @show tasks[1][:Ns]
    @test tasks[1][:Ns] === (20, 10)
    # a parameter whose own name ends in a tuple suffix cannot be swept
    tasks, _ = generate_method_tasks(create_param_dict(:dt__1 => 0.1), [:dt__1], [[0.2, 0.3]])
    @show [t[:dt__1] for t in tasks]
    @test all(t -> t[:dt__1] == 0.1, tasks)
    # padding past the end mixes Float zeros into integer tuples
    tasks, _ = generate_method_tasks(create_param_dict(:Ns => (10, 10)), [:Ns__4], [[5]])
    @show tasks[1][:Ns]
end
