# Tabulated data as a method (tabulated_method / tabulated_data)
@testset "Tabulated data" begin
    register_stat!(:l1error, :time)
    shared = create_param_dict(:N => 20, :cfl => 0.5, :sim_func_name => :advection_solver_1d)
    paper = tabulated_method(Dict(:N => [40, 80, 160], :l1error => [2.1e-3, 5.4e-4, 1.4e-4], :note => ["a", "b", "c"]);
                             key = :N, ignore = collect(keys(shared)))
    @test paper[:sim_func_name] === :tabulated_data && paper[:table_key] === :N && paper[:N] == 40
    @test PDEStudioCore.resolve_dynamic_function(:tabulated_data) === tabulated_data   # found in every target module
    @test_throws ArgumentError tabulated_method(Dict(:N => [1, 2], :e => [1.0]); key = :N)   # unequal columns
    @test_throws ArgumentError tabulated_method(Dict(:N => [1, 2], :e => [1.0, 2.0]))         # no key, no x column

    config = SimulationConfig(shared, create_method_dict(:upwind => create_param_dict(:scheme => "upwind"), :paper => paper);
                              varied = create_varied_dict(:N => [40, 80, 320]))
    tasks = generate_tasks(config)
    paper_tasks = filter(t -> t[:sim_func_name] === :tabulated_data, tasks)
    @test length(paper_tasks) == 3 && !any(haskey(t, :cfl) for t in paper_tasks)   # the shared parameters are ignored
    summary = run_all_simulations(config; calculate_stats = true)
    @test isempty(summary.failed)
    task(N) = only(filter(t -> t[:N] == N, paper_tasks))         # (`:ignore` is not part of a task)
    d40 = load_sim_data(task(40))
    @test d40.stats[:l1error] == [SVector(2.1e-3)]              # shaped like the registered statistic (over time)
    @test !haskey(d40.stats, :note)                              # text columns are not statistics
    @test does_sim_data_exist(task(80))
    @test !does_sim_data_exist(task(320))                        # no row: a gap
    @test tabulated_data(merge(paper, Dict(:N => 320))) isa NoSimData
    @test tabulated_data(merge(paper, Dict(:N => 80.0))).stats[:l1error] == [SVector(5.4e-4)]   # 80.0 finds the row 80
    # the statistic survives the statistics pass (it is not recomputed while present)
    calculate_all_stats!(d40; save = false)
    @test d40.stats[:l1error] == [SVector(2.1e-3)]

    # a profile over x: a static 1D dataset
    curve = tabulated_method(Dict(:x => [0.5, 0.0, 1.0], :u => [1.0, 0.0, 2.0]); ignore = collect(keys(shared)))
    prof = tabulated_data(curve)
    @test prof isa ESimData && prof.axes[1] == [0.0, 0.5, 1.0] && [v[1] for v in prof.u] == [0.0, 1.0, 2.0]
    @test !has_time(prof)
    # the table round-trips through the parameter normalisation (configuration files, hashes)
    @test get_clean_params(paper)[:table] == paper[:table]
    delete_sim_data(Dict(:sim_func_name => :tabulated_data))
    delete_stat!(:l1error)
end
