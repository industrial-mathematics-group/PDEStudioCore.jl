# Fixes of the A2 review of v0.6.2 (reviews/2026-11-23-v0.6.2-codex.md), one case per finding
review_data(p, v) = create_sim_data([0.0, 1.0], fill(v, 2), p)
typed_solver(p::ParamDict) = review_data(p, p[:k] isa AbstractString ? 2.0 : 1.0)
weights_solver(p::ParamDict) = (p[:weights][1] = 9.0; review_data(p, 1.0))
const REVIEW_FAIL = Ref(false)
toggled_solver(p::ParamDict) = REVIEW_FAIL[] ? error("failed rerun") : review_data(p, 1.0)
marking_post(d) = (d.metadata[:marked] = true; true)
one_reference(p) = x -> SVector(1.0)
two_reference(p) = x -> SVector(2.0)
constant_solver(p::ParamDict) = review_data(p, 1.0)

@testset "Review fixes (v0.6.2)" begin
    set_save_path!(mktempdir())

    # 1. A string that reads as another value ("1", "Float32") doesn't share the hash of that value; a file stored
    #    under the earlier hash is found by its stored parameters
    @test calculate_hash(Dict(:k => 1)) != calculate_hash(Dict(:k => "1"))
    @test calculate_hash(Dict(:k => true)) != calculate_hash(Dict(:k => "true")) && calculate_hash(Dict(:k => Float32)) != calculate_hash(Dict(:k => "Float32"))
    @test PDEStudioCore._hash_text("1") == "\"1\"" && PDEStudioCore._hash_text("upwind") == "upwind" && PDEStudioCore._hash_text("SlipWall(1.0)") == "SlipWall(1.0)"
    @test val2str("1.5f0") == "1.5f0"   # (`val2str` itself is unchanged: frontends write literal text through it)
    s = run_all_simulations(SimulationConfig(create_param_dict(:sim_func_name => :typed_solver, :k => 1);
                                             varied = create_varied_dict(:k => Any[1, "1"])))
    @test length(s.tasks) == 2 && length(s.ran) == 2
    @test load_sim_data(create_param_dict(:sim_func_name => :typed_solver, :k => "1")).u[1][1] == 2.0
    @test load_sim_data(create_param_dict(:sim_func_name => :typed_solver, :k => 1)).u[1][1] == 1.0
    p = create_param_dict(:sim_func_name => :typed_solver, :k => "Float32")
    clean = get_clean_params(p)
    path = save_sim_data(typed_solver(p))
    legacy_hash = PDEStudioCore._legacy_hash(clean)
    @test legacy_hash !== nothing && isnothing(PDEStudioCore._legacy_hash(get_clean_params(create_param_dict(:k => "a"))))
    legacy = joinpath(dirname(path), replace(basename(path), calculate_hash(clean) => legacy_hash))
    mv(path, legacy)
    @test PDEStudioCore._find_file(p) == legacy && load_sim_data(p).u[1][1] == 2.0
    q = create_param_dict(:sim_func_name => :typed_solver, :k => "Int64")   # (same legacy text, other parameters)
    mv(legacy, joinpath(dirname(legacy), replace(basename(legacy), legacy_hash => PDEStudioCore._legacy_hash(get_clean_params(q)))))
    @test isnothing(PDEStudioCore._find_file(q))   # (its stored parameters are p's)

    # 2. The solver gets a deep copy: what it changes inside arrays doesn't reach the caller
    p = create_param_dict(:weights => [1.0, 2.0])
    run_smart_simulation(weights_solver, p)
    @test p[:weights] == [1.0, 2.0] && does_sim_data_exist(p)

    # 3. A failed recomputation leaves the stored data to statistics and post-processing alone
    REVIEW_FAIL[] = false
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :toggled_solver))
    run_all_simulations(cfg)
    cfg.postprocess = :marking_post
    REVIEW_FAIL[] = true
    s = run_all_simulations(cfg; force_overwrite = true, calculate_stats = true)
    @test length(s.failed) == 1 && s.postprocessing == Dict(:not_run => 1) && s.stats == Dict(:not_run => 1)
    @test !haskey(load_sim_data(cfg.shared).metadata, :marked)
    REVIEW_FAIL[] = false

    # 4. A cached conversion is still marked as one when read from the cache (it never becomes the native run)
    p = create_param_dict(:case => :cached_conversion)
    save_sim_data(review_data(p, 1.0))
    enable_cache!(true)
    try
        first_read, second_read = load_sim_data(p, :lagrangian), load_sim_data(p, :lagrangian)
        @test first_read.metadata[:derived] === second_read.metadata[:derived] === :conversion
        @test load_sim_data(get_file_name(p); key = "conv_L").metadata[:derived] === :conversion
        @test !haskey(load_sim_data(p).metadata, :derived)
        set_save_path!(mktempdir())
        @test_logs (:warn, r"not saved") match_mode = :any calculate_all_stats!(second_read)
        @test !does_sim_data_exist(p)
    finally
        enable_cache!(false)
    end

    # 5. Statistics evaluated with another reference are evaluated again
    set_save_path!(mktempdir())
    p = create_param_dict(:sim_func_name => :constant_solver)
    cfg = SimulationConfig(p; reference = :one_reference)
    run_all_simulations(cfg; calculate_stats = true)
    @test load_sim_data(p).stats[:l1error][1] == 0.0
    @test run_all_simulations(cfg; calculate_stats = true).stats == Dict(:cached => 1)
    cfg.reference = :two_reference
    s = run_all_simulations(cfg; calculate_stats = true)
    @test s.stats == Dict(:ran => 1) && load_sim_data(p).stats[:l1error][1] > 0
    @test run_all_simulations(cfg; calculate_stats = true).stats == Dict(:cached => 1)
    @test PDEStudioCore._reference_record(:two_reference, two_reference) != PDEStudioCore._reference_record(:one_reference, one_reference)
    @test PDEStudioCore._reference_record(:x, nothing) == ""

    # 6. Float16 particles on grid nodes: finite weights, the particles' values
    d16 = create_sim_data(SVector.(Float16[0, 1]), Float16[2, 2], ParamDict())
    out = convert_to_eulerian(d16, (2,))
    @test eltype(out.u) == SVector{1, Float16} && [v[1] for v in out.u] == Float16[2, 2]

    # 7. A statistic defined for some components only is kept; 13. the mass error is the measured one
    d = create_sim_data([0.0, 1.0], fill(SVector(1.0, 2.0), 2), ParamDict())
    calculate_all_stats!(d, x -> SVector(0.0, 2.0); save = false)
    @test isnan(d.stats[:relative_mass][1]) && d.stats[:relative_mass][2] == 1.0
    @test d.stats[:mass_error][2] == 0.0
    @test PDEStudioCore.is_all_nan([SVector(NaN, NaN)]) && !PDEStudioCore.is_all_nan([SVector(NaN, 1.0)])

    # 12. A single value for a statistic that keeps dimensions is refused
    @test_throws DimensionMismatch add_stat!(d, :spatial, 1.0, :space)
    @test add_stat!(d, :scalar, 1.0, Symbol[]) == SVector(1.0, 1.0)

    # 8. An unreadable data file: the run reports it and returns its summary
    set_save_path!(mktempdir())
    p = create_param_dict(:sim_func_name => :constant_solver)
    file = save_sim_data(constant_solver(p))
    open(io -> truncate(io, 0), file, "w")
    s = @test_logs min_level = Base.CoreLogging.Error match_mode = :any run_all_simulations(SimulationConfig(p))
    @test length(s.failed) == 1 && s.files == [nothing]

    # 9. Upwind takes the upstream neighbour for negative speeds (at CFL 1 an exact shift)
    cfg = test_advection_1d()
    pa = merge(cfg.shared, cfg.methods[:upwind], create_param_dict(:N => 4, :c => -1.0, :T => 0.25, :cfl => 1.0))
    da = PDEStudioCore.Examples.solve_advection_1d(pa)
    @test [v[1] for v in da.u[:, 2]] ≈ sin.(2π .* ([0, 0.25, 0.5, 0.75] .+ 0.25)) atol = 1e-12

    # 10. One column per parameter in every row of the table
    set_save_path!(mktempdir())
    save_sim_data(review_data(create_param_dict(:solver => "alpha"), 1.0))
    save_sim_data(review_data(create_param_dict(:param_solver => "beta"), 2.0))
    tab = sim_data_table()
    @test sort(collect(skipmissing(tab.param_param_solver))) == ["alpha"] && sort(collect(skipmissing(tab.param_solver))) == ["beta"]

    # 11. Health summary of BigFloat data
    h = check_data(create_sim_data(BigFloat[0, 1], BigFloat[1, 2], ParamDict()))
    @test h.C1_Mean == [1.5] && h.C1_Max == [2.0]

    set_save_path!(mktempdir())
end
