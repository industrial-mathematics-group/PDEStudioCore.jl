POST_CALLS = Ref(0)  # non-const so the suite can be re-run in one session
count_post(data) = (POST_CALLS[] += 1; nothing)  # returns nothing: nothing is saved
keep_post(data) = true                            # saves the (unchanged) data again

@testset "SimulationConfig" begin
    # Varied keys must also appear in the shared (or method) parameters.
    shared = Dict("cfl" => 0.5, :N => 5, :sim_func_name => :advection_solver_1d)
    methods = Dict(:upwind => Dict(:scheme => "upwind"), "lax_friedrichs" => Dict(:scheme => "lax_friedrichs"))
    cfg = SimulationConfig(shared, methods; varied = Dict(:N => [10, 20]), reference = "exact_advection_factory")
    @test cfg.shared isa ParamDict && cfg.shared[:cfl] == 0.5
    @test cfg.methods isa MethodDict && cfg.defaults == [:lax_friedrichs, :upwind]  # default: all methods
    @test cfg.varied isa VariedDict && cfg.varied[:N] == [10, 20]
    @test cfg.reference === :exact_advection_factory && cfg.postprocess === nothing && isempty(cfg.sources)
    @test length(generate_tasks(cfg)) == 4
    @test occursin("SimulationConfig", repr("text/plain", cfg))

    # Only the current keyword and field names exist
    full = SimulationConfig(shared, methods, [:upwind]; varied = Dict(:N => [10]), reference = :exact_advection_factory,
                            postprocess = :count_post, sources = "not_loaded_here.jl")
    @test full.varied[:N] == [10] && full.postprocess === :count_post && full.sources == ["not_loaded_here.jl"]
    @test_throws MethodError SimulationConfig(shared, methods; varied_params = Dict(:N => [10]))
    @test_throws Exception full.active_methods  # ErrorException (FieldError on Julia ≥ 1.12)
    @test_throws ArgumentError full.varied_params = Dict(:N => [30])

    # Assigning fields accepts the same loose input as the constructor
    full.reference = "exact_advection_factory"
    full.sources = "a.jl"
    full.defaults = :lax_friedrichs
    full.shared = Dict("N" => 3)
    full.varied = Dict("N" => 1:3)
    @test full.reference === :exact_advection_factory && full.sources == ["a.jl"]
    @test full.defaults == [:lax_friedrichs] && full.shared == ParamDict(:N => 3) && full.varied[:N] == [1, 2, 3]

    # Without methods, the shared parameters run once
    @test length(generate_tasks(SimulationConfig(Dict(:sim_func_name => :advection_solver_1d, :N => 8)))) == 1

    # A varied key used by only one method does not duplicate the runs of the others
    m2 = Dict(:a => Dict(:scheme => "upwind", :theta => 0.5), :b => Dict(:scheme => "lax_friedrichs"))
    cfg2 = SimulationConfig(Dict(:sim_func_name => :advection_solver_1d, :N => 8), m2; varied = Dict(:theta => [0.1, 0.2, 0.3]))
    @test length(generate_tasks(cfg2)) == 4  # 3 for :a, 1 for :b

    # Reference methods are skipped and unused varied keys are reported
    cfg3 = SimulationConfig(Dict(:sim_func_name => :advection_solver_1d, :N => 8),
                            Dict(:upwind => Dict(:scheme => "upwind")), [:upwind, :analytic];
                            varied = Dict(:typo => [1, 2]))
    tasks3 = @test_logs (:warn, r"typo") match_mode = :any generate_tasks(cfg3)
    @test length(tasks3) == 1
    @test is_reference_method(:analytic) && is_reference_method(:exact_solution)
    @test !is_reference_method(:inexact_newton) && !is_reference_method(:construe)
    # A method named like a reference but with a solver of its own is skipped too, with a warning
    cfg4 = SimulationConfig(Dict(:N => 8),
                            Dict(:godunov_exact_riemann => Dict(:sim_func_name => :advection_solver_1d),
                                 :upwind => Dict(:scheme => "upwind", :sim_func_name => :advection_solver_1d)))
    empty!(PDEStudioCore._WARNED_REFERENCE_NAMES)  # warned once per session: keep the suite re-runnable
    tasks4 = @test_logs (:warn, r"godunov_exact_riemann.*marks it as a reference") match_mode = :any generate_tasks(cfg4)
    @test length(tasks4) == 1
end

@testset "Pipeline: sweep, statistics & loading" begin
    shared = create_param_dict(:cfl => 0.5, :N => 75, :sim_func_name => :advection_solver_1d)
    methods = create_method_dict(:upwind => Dict(:scheme => "upwind"), :lax_friedrichs => Dict(:scheme => "lax_friedrichs"))
    config = SimulationConfig(shared, methods, [:upwind, :lax_friedrichs];
                              varied = Dict(:N => [50, 100]), reference = :exact_advection_factory)
    run_all_simulations(config; force_overwrite = true, calculate_stats = true)

    for scheme in ["upwind", "lax_friedrichs"], N in [50, 100]
        p = create_param_dict(:scheme => scheme, :N => N, :cfl => 0.5, :sim_func_name => :advection_solver_1d)
        @test does_sim_data_exist(p)
        sim = load_sim_data(p)
        @test sim isa ESimData && sim.stats[:Solution] === sim.u
        @test haskey(sim.stats, :l1error) && haskey(sim.stats, :mass)
        initial_mass = sim.stats[:mass][1][1]
        @test all(m -> isapprox(m[1], initial_mass; rtol = 1e-12), sim.stats[:mass])
    end

    results = [load_sim_data(p) for p in generate_tasks(config)]
    @test length(results) == 4 && all(r -> r isa ESimData, results)

    lf(N) = load_sim_data(create_param_dict(:scheme => "lax_friedrichs", :N => N, :cfl => 0.5, :sim_func_name => :advection_solver_1d))
    @test lf(100).stats[:l1error][end][1] < lf(50).stats[:l1error][end][1]

    # A second run finds everything on disk and touches nothing
    file = get_file_name(first(generate_tasks(config)))
    stamp = mtime(file)
    sleep(0.05)
    run_all_simulations(config; calculate_stats = true)
    @test mtime(file) == stamp
end

@testset "Pipeline: tuple sweeps" begin
    base_params = create_param_dict(:Ns => (10, 10), :scheme => "upwind", :cfl => 0.5)
    tasks, grid_indices = generate_method_tasks(base_params, [:Ns__x, :Ns__2], [[20, 40], [15, 30]])
    @test length(tasks) == 4 && length(grid_indices) == 4
    @test [t[:Ns] for t in tasks] == [(20, 15), (40, 15), (20, 30), (40, 30)]
    @test all(t[:Ns] isa Tuple{Int, Int} for t in tasks)
    # `__0` is not a tuple entry: the key is an ordinary (here absent) parameter
    tasks0, _ = generate_method_tasks(base_params, [:Ns__0], [[1, 2]])
    @test all(t -> t == base_params, tasks0)

    # Several entries at once: `__all` / `__xy` set them to the same value (square grids)
    tasks_all, grid_all = generate_method_tasks(base_params, [:Ns__all], [[20, 40]])
    @test [t[:Ns] for t in tasks_all] == [(20, 20), (40, 40)] && grid_all == [(1,), (2,)]
    @test all(t[:Ns] isa Tuple{Int, Int} for t in tasks_all)
    tasks_xy, _ = generate_method_tasks(base_params, [:Ns__xy], [[20, 40]])
    @test tasks_xy == tasks_all
    # ... and produce exactly the tasks (hence file hashes) of the explicit tuple sweep
    tasks_tup, _ = generate_method_tasks(base_params, [:Ns], [[(20, 20), (40, 40)]])
    @test tasks_all == tasks_tup
    @test calculate_hash(tasks_all[1]) == calculate_hash(tasks_tup[1])
    # a subset of the entries keeps the others; the suffix may mix with single-entry keys
    tasks_xz, _ = generate_method_tasks(create_param_dict(:Ns => (1, 2, 3)), [:Ns__xz, :Ns__y], [[7], [9]])
    @test tasks_xz[1][:Ns] == (7, 9, 7)
    @test PDEStudioCore._split_varied_key(:Ns__12) == (:Ns, [12])
    @test PDEStudioCore._split_varied_key(:Ns__zx) == (:Ns, [1, 3])
    @test PDEStudioCore._split_varied_key(:Ns__ab) == (:Ns__ab, nothing)   # not a tuple suffix
    # a parameter whose own name looks like a suffix key is an ordinary key
    tasks_dt, _ = generate_method_tasks(create_param_dict(:dt__1 => 0.1), [:dt__1], [[0.2, 0.3]])
    @test [t[:dt__1] for t in tasks_dt] == [0.2, 0.3]
    cfg_dt = SimulationConfig(create_param_dict(:dt__1 => 0.1, :sim_func_name => :dummy_tuple_solver);
                              varied = create_varied_dict(:dt__1 => [0.2]))
    @test only(generate_tasks(cfg_dt))[:dt__1] == 0.2
    # Bool tuples stay Bool tuples
    tasks_b, _ = generate_method_tasks(create_param_dict(:flags => (true, true)), [:flags__y], [[false]])
    @test tasks_b[1][:flags] === (true, false)
    # a suffix on a scalar parameter is a configuration error, reported as such
    @test_throws ArgumentError generate_method_tasks(create_param_dict(:N => 10), [:N__all], [[20]])
    @test_throws ArgumentError generate_tasks(SimulationConfig(create_param_dict(:N => 10, :sim_func_name => :dummy_tuple_solver);
                                                               varied = create_varied_dict(:N__x => [20])))
    cfg_sq = SimulationConfig(create_param_dict(:Ns => (10, 10), :sim_func_name => :dummy_tuple_solver);
                              varied = create_varied_dict(:Ns__all => [20, 30]))
    @test [t[:Ns] for t in generate_tasks(cfg_sq)] == [(20, 20), (30, 30)]

    # `:ignore` drops shared keys but is not itself a parameter (so it is not hashed)
    ign = assemble_params(create_param_dict(:a => 1, :b => 2), create_method_dict(:m => Dict(:c => 3, :ignore => [:b])), :m)
    @test ign == create_param_dict(:a => 1, :c => 3)

    shared = create_param_dict(:Ns => (10, 10), :cfl => 0.5, :sim_func_name => :dummy_tuple_solver)
    methods = create_method_dict(:upwind => create_param_dict(:scheme => "upwind"))
    config = SimulationConfig(shared, methods, [:upwind]; varied = create_varied_dict(:Ns__1 => [20, 30], :Ns__y => [5, 15]))
    run_all_simulations(config; force_overwrite = true)
    for Nx in [20, 30], Ny in [5, 15]
        p = create_param_dict(:Ns => (Nx, Ny), :scheme => "upwind", :cfl => 0.5, :sim_func_name => :dummy_tuple_solver)
        @test does_sim_data_exist(p)
        sim = load_sim_data(p)
        @test sim.params[:Ns] == (Nx, Ny) && size(sim.u) == (Nx, Ny, 2)
    end
end

@testset "Pipeline robustness" begin
    POST_CALLS[] = 0
    shared = Dict(:N => 6, :sim_func_name => :advection_solver_1d)
    methods = Dict(:fail => Dict(:sim_func_name => :failing_solver),
                   :empty => Dict(:sim_func_name => :empty_solver),
                   :mutate => Dict(:sim_func_name => :mutating_solver),
                   :ok => Dict(:scheme => "upwind"))
    cfg = SimulationConfig(shared, methods; postprocess = :count_post)
    @test_logs (:error, r"Simulation failed") match_mode = :any run_all_simulations(cfg; calculate_stats = true)

    tasks = generate_tasks(cfg)
    @test length(tasks) == 4
    exists = Dict(t[:sim_func_name] => does_sim_data_exist(t) for t in tasks)
    @test !exists[:failing_solver] && !exists[:empty_solver]
    @test exists[:mutating_solver] && exists[:advection_solver_1d]
    # Results are stored under the task parameters even if the solver modified its parameters
    mutated = only(filter(t -> t[:sim_func_name] === :mutating_solver, tasks))
    @test !haskey(load_sim_data(mutated).params, :injected)
    @test POST_CALLS[] == 2  # post-processing ran for the two datasets that exist
end

@testset "Pipeline: statistics are retried once a reference exists" begin
    SOLVER_CALLS[] = 0
    shared = create_param_dict(:N => 12, :scheme => "upwind", :cfl => 0.5, :sim_func_name => :counting_solver)
    cfg_noref = SimulationConfig(shared)
    run_all_simulations(cfg_noref; force_overwrite = true, calculate_stats = true)
    p = only(generate_tasks(cfg_noref))
    @test SOLVER_CALLS[] == 1
    @test haskey(load_sim_data(p).stats, :mass) && !haskey(load_sim_data(p).stats, :l1error)
    entries = load_sim_data(calculate_hash(get_clean_params(p))[1:12])
    @test entries["evaluated_with_reference"] == false

    # Without a reference nothing is recomputed ...
    file = get_file_name(p)
    stamp = mtime(file)
    sleep(0.05)
    run_all_simulations(cfg_noref; calculate_stats = true)
    @test mtime(file) == stamp && SOLVER_CALLS[] == 1

    # ... but adding a reference evaluates the dropped error statistics without rerunning the solver
    cfg_ref = SimulationConfig(shared; reference = :exact_advection_factory)
    run_all_simulations(cfg_ref; calculate_stats = true)
    @test SOLVER_CALLS[] == 1
    @test haskey(load_sim_data(p).stats, :l1error)

    # force_stats recomputes statistics but still does not rerun the solver
    stamp = mtime(get_file_name(p))
    sleep(0.05)
    run_all_simulations(cfg_ref; calculate_stats = true, force_stats = true)
    @test SOLVER_CALLS[] == 1 && mtime(get_file_name(p)) != stamp

    # A sweep without values produces no tasks (and says so)
    @test isempty(@test_logs (:warn, r"no values") match_mode = :any generate_tasks(SimulationConfig(shared; varied = Dict(:N => Int[]))))
end

@testset "Pipeline: post-processing keeps the statistics bookkeeping" begin
    shared = create_param_dict(:N => 10, :scheme => "upwind", :cfl => 0.5, :sim_func_name => :advection_solver_1d,
                               :test_mode => "post-keep")
    cfg = SimulationConfig(shared; postprocess = :keep_post)
    run_all_simulations(cfg; calculate_stats = true)   # no reference: the error statistics are dropped
    p = only(generate_tasks(cfg))
    file = get_file_name(p)
    entries = load_sim_data(calculate_hash(get_clean_params(p))[1:12])
    @test haskey(entries, "evaluated_stats") && entries["evaluated_with_reference"] == false
    # so a rerun doesn't reload the data for statistics that were evaluated already
    required = sort!(Symbol[k for k in keys(get_stat_registry()) if k !== :Solution])
    @test !PDEStudioCore._needs_stats(file, required, false)
end

@testset "Pipeline: source files" begin
    src = joinpath(mktempdir(), "sourced_solver.jl")
    write(src, """
    function sourced_solver(params)
        x = collect(range(0.0, 1.0, length = params[:n]))
        return create_sim_data(x, ones(length(x)), params)
    end
    """)
    cfg = SimulationConfig(Dict(:sim_func_name => :sourced_solver, :n => 7); sources = src)
    run_all_simulations(cfg)
    p = only(generate_tasks(cfg))
    @test does_sim_data_exist(p)
    sim = load_sim_data(p)
    @test sim isa ESimData{1, 1, 1, Float64} && !has_time(sim)
    entries = load_sim_data(calculate_hash(get_clean_params(p))[1:12])
    @test haskey(entries, "sources") && haskey(entries["sources"], abspath(src))
    # with `load_sources = false` the caller has included the sources: they don't run again, the digests are stored
    write(src, "error(\"must not run\")")
    run_all_simulations(cfg; force_overwrite = true, load_sources = false)
    entries = load_sim_data(calculate_hash(get_clean_params(p))[1:12])
    @test haskey(entries["sources"], abspath(src))
    @test_throws LoadError run_all_simulations(cfg; force_overwrite = true)
end

@testset "Pipeline: run summary" begin
    shared = Dict(:N => 6, :sim_func_name => :advection_solver_1d, :test_mode => "summary")
    methods = Dict(:fail => Dict(:sim_func_name => :failing_solver), :empty => Dict(:sim_func_name => :empty_solver),
                   :ok => Dict(:scheme => "upwind"))
    cfg = SimulationConfig(shared, methods; postprocess = :count_post)
    s = @test_logs (:error, r"Simulation failed") match_mode = :any run_all_simulations(cfg; calculate_stats = true)
    @test s isa RunSummary && !s.dry_run && length(s.tasks) == 3 && s.elapsed >= 0
    @test length(s.ran) == 1 && s.ran[1][:scheme] == "upwind" && isempty(s.cached) && isempty(s.changed)
    @test length(s.empty) == 1 && s.empty[1][:sim_func_name] === :empty_solver
    @test length(s.failed) == 1 && first(s.failed[1])[:sim_func_name] === :failing_solver
    @test last(s.failed[1]) == "intentional failure"
    @test s.stats == Dict(:ran => 1, :missing => 2) && s.postprocessing == Dict(:ran => 1, :missing => 2)
    text = repr("text/plain", s)
    @test occursin("3 task(s)", text) && occursin("1 ran", text) && occursin("1 failed", text)
    @test occursin("failed: N = 6", text) && occursin("intentional failure", text) && !occursin("sim_func_name", text)
    @test repr(s) == "RunSummary(3 tasks: 1 ran, 0 cached, 1 failed)"
    # a rerun: the result is cached, its statistics and post-processing are done already
    s2 = @test_logs (:error, r"Simulation failed") match_mode = :any run_all_simulations(cfg; calculate_stats = true)
    @test isempty(s2.ran) && length(s2.cached) == 1 && s2.stats[:cached] == 1 && s2.postprocessing[:skipped] == 1
    # failing statistics and post-processing are listed, too
    s3 = @test_logs (:error, r"Statistics failed") (:error, r"Post-processing failed") match_mode = :any run_all_simulations(SimulationConfig(Dict(:N => 6, :sim_func_name => :advection_solver_1d, :scheme => "upwind",
                                                   :test_mode => "summary"); reference = :failing_solver,
                                              postprocess = :failing_solver);
                             calculate_stats = true, force_stats = true)
    @test length(s3.stats_failed) == 1 && last(s3.stats_failed[1]) == "intentional failure"
    @test length(s3.postprocessing_failed) == 1 && s3.postprocessing == Dict(:failed => 1)
    @test occursin("post-processing failed", repr("text/plain", s3))
    @test run_all_simulations(SimulationConfig(shared; varied = Dict(:N => Int[]))) isa RunSummary
    @test_throws ArgumentError run_all_simulations(cfg; on_changed_sources = :sometimes)
end

@testset "Pipeline: post-processing record, changed sources, dry run" begin
    src = joinpath(mktempdir(), "record_solver.jl")
    solver_code = """
    function record_solver(params)
        x = collect(range(0.0, 1.0, length = params[:n]))
        return create_sim_data(x, fill(1.0, length(x)), params)
    end
    """
    write(src, solver_code)
    config(; post = :count_post, ns = [5, 6]) =
        SimulationConfig(Dict(:sim_func_name => :record_solver, :n => 5); varied = Dict(:n => ns), sources = src, postprocess = post)
    cfg = config()
    files() = [get_file_name(p) for p in generate_tasks(cfg)]
    POST_CALLS[] = 0
    s = run_all_simulations(cfg)
    @test length(s.ran) == 2 && s.postprocessing == Dict(:ran => 2) && POST_CALLS[] == 2
    record = PDEStudioCore.jldopen(f -> f["postprocessed"], files()[1], "r")
    @test record["name"] == "count_post" && length(record["sources"]) == 1

    # the same post-processor on the same data: skipped; force_postprocess runs it again
    s = run_all_simulations(cfg)
    @test length(s.cached) == 2 && s.postprocessing == Dict(:skipped => 2) && POST_CALLS[] == 2
    run_all_simulations(cfg; force_postprocess = true)
    @test POST_CALLS[] == 4
    # new data: post-processed again
    s = run_all_simulations(cfg; force_overwrite = true)
    @test length(s.ran) == 2 && s.postprocessing == Dict(:ran => 2) && POST_CALLS[] == 6
    # another post-processor
    keep_cfg = config(post = :keep_post)
    @test run_all_simulations(keep_cfg).postprocessing == Dict(:ran => 2)
    @test run_all_simulations(keep_cfg).postprocessing == Dict(:skipped => 2)   # (its rewrite keeps the record)
    @test run_all_simulations(cfg).postprocessing == Dict(:ran => 2) && POST_CALLS[] == 8

    # other source code: the stored results are kept with a warning (every run, until recomputed) ...
    write(src, solver_code * "# changed\n")
    s = @test_logs (:warn, r"2 stored result\(s\) were made with other source code") (:warn, r"2 dataset\(s\) were post-processed by another version of count_post") match_mode = :any run_all_simulations(cfg)
    @test length(s.changed) == 2 && length(s.cached) == 2 && isempty(s.ran)
    @test occursin("changed code: 2", repr("text/plain", s)) && occursin("2 outdated", repr("text/plain", s))
    # (the post-processor may have changed with the sources: it isn't applied again to data it processed ...)
    @test s.postprocessing == Dict(:outdated => 2) && POST_CALLS[] == 8
    # (... unless forced)
    s = @test_logs (:warn, r"other source code") match_mode = :any run_all_simulations(cfg; force_postprocess = true)
    @test s.postprocessing == Dict(:ran => 2) && POST_CALLS[] == 10
    s = @test_logs (:warn, r"other source code") match_mode = :any run_all_simulations(cfg)
    @test length(s.changed) == 2 && s.postprocessing == Dict(:skipped => 2)
    # ... silently with :ignore ...
    s = @test_logs min_level = Base.CoreLogging.Warn run_all_simulations(cfg; on_changed_sources = :ignore)
    @test isempty(s.changed) && length(s.cached) == 2
    stamps = mtime.(files())
    # ... a dry run says what :recompute would do, and writes nothing ...
    s = run_all_simulations(cfg; on_changed_sources = :recompute, dry_run = true)
    @test s.dry_run && length(s.ran) == 2 && length(s.changed) == 2 && s.postprocessing == Dict(:ran => 2)
    @test mtime.(files()) == stamps && POST_CALLS[] == 10
    @test occursin("(dry run)", repr("text/plain", s)) && occursin("2 would run", repr("text/plain", s))
    # ... and :recompute runs them again
    s = run_all_simulations(cfg; on_changed_sources = :recompute)
    @test length(s.ran) == 2 && length(s.changed) == 2 && POST_CALLS[] == 12
    s = @test_logs min_level = Base.CoreLogging.Warn run_all_simulations(cfg)
    @test isempty(s.changed) && length(s.cached) == 2

    # a dry run of a larger sweep: only the new task would run (and get its post-processing)
    big = config(ns = [5, 6, 7])
    s = run_all_simulations(big; dry_run = true)
    @test length(s.ran) == 1 && s.ran[1][:n] == 7 && length(s.cached) == 2
    @test s.postprocessing == Dict(:ran => 1, :skipped => 2)
    @test !does_sim_data_exist(s.ran[1]) && POST_CALLS[] == 12
    # (the new task's data: it ran with the new sources)
    @test length(run_all_simulations(big).ran) == 1 && POST_CALLS[] == 13
end

# Callable objects as solver and post-processor (resolved by name like functions)
struct ScaledSolver
    scale::Float64
end
(s::ScaledSolver)(params) = create_sim_data(collect(range(0.0, 1.0, length = params[:n])), fill(s.scale, params[:n]), params)
scaled_solver = ScaledSolver(2.0)
struct MarkPost end
(::MarkPost)(data) = nothing
mark_post = MarkPost()

@testset "Pipeline: callable objects as solver and post-processor" begin
    cfg = SimulationConfig(Dict(:sim_func_name => :scaled_solver, :n => 4); postprocess = :mark_post)
    s = run_all_simulations(cfg)
    @test length(s.ran) == 1 && isempty(s.failed) && s.postprocessing == Dict(:ran => 1)
    path = get_file_name(only(generate_tasks(cfg)))
    @test PDEStudioCore.jldopen(f -> (f["provenance"]["solver"], f["postprocessed"]["name"]), path, "r") ==
          ("ScaledSolver", "mark_post")
    @test run_all_simulations(cfg).postprocessing == Dict(:skipped => 1)
end
