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

    # 1. Hash format 3 (0.7): every top-level string is hashed quoted, so no two values share a name ("1" and 1, "1" and
    #    the three characters "\"1\""); a struct stored as its text hashes like that text
    @test calculate_hash(Dict(:k => 1)) != calculate_hash(Dict(:k => "1")) != calculate_hash(Dict(:k => "\"1\""))
    @test calculate_hash(Dict(:k => true)) != calculate_hash(Dict(:k => "true")) && calculate_hash(Dict(:k => Float32)) != calculate_hash(Dict(:k => "Float32"))
    @test PDEStudioCore._hash_text("1") == "\"1\"" && PDEStudioCore._hash_text("\"1\"") == "\"\\\"1\\\"\"" && PDEStudioCore._hash_text(1) == "1"
    @test val2str("1.5f0") == "1.5f0"   # (`val2str` itself is unchanged: frontends write literal text through it)
    s = run_all_simulations(SimulationConfig(create_param_dict(:sim_func_name => :typed_solver, :k => 1);
                                             varied = create_varied_dict(:k => Any[1, "1", "\"1\""])))
    @test length(s.tasks) == 3 && length(s.ran) == 3 && length(unique(s.files)) == 3
    @test load_sim_data(create_param_dict(:sim_func_name => :typed_solver, :k => "1")).u[1][1] == 2.0
    @test load_sim_data(create_param_dict(:sim_func_name => :typed_solver, :k => 1)).u[1][1] == 1.0
    # Hash format 3: keys as `repr`, so a key can't forge other pairs; `nothing` apart from the type `Nothing`
    @test calculate_hash(Dict(:a => "label", :b => 2)) != calculate_hash(Dict(Symbol("a => \"label\", b") => 2))
    @test calculate_hash(Dict(:k => nothing)) != calculate_hash(Dict(:k => Nothing))
    @test calculate_hash(Dict(:k => missing)) != calculate_hash(Dict(:k => Missing))
    # a lookup checks the stored parameters: a file of another run under this name is never returned or replaced
    dir = joinpath(get_save_path(), "data")
    p1, pstr = create_param_dict(:sim_func_name => :typed_solver, :k => 1), create_param_dict(:sim_func_name => :typed_solver, :k => "1")
    f_str = get_file_name(pstr)
    forged = replace(f_str, calculate_hash(pstr) => calculate_hash(p1))   # (another run's file under p1's name)
    rm(get_file_name(p1)); cp(f_str, forged)
    PDEStudioCore._invalidate_index!()
    @test isnothing(PDEStudioCore._find_file(p1)) && get_file_name(pstr) == f_str
    path1 = save_sim_data(typed_solver(p1); overwrite = true, verbose = false)
    @test path1 != forged && load_sim_data(p1).u[1][1] == 1.0 && load_sim_data(forged; key = "raw").params[:k] == "1"
    @test PDEStudioCore._new_file_name("ab"^32, dir, "T") == joinpath(dir, "T_$("ab"^32).jld2")
    touch(joinpath(dir, "T_$("ab"^32).jld2"))
    @test PDEStudioCore._new_file_name("ab"^32, dir, "T") == joinpath(dir, "T_$("ab"^32)_2.jld2")
    rm(joinpath(dir, "T_$("ab"^32).jld2")); rm(forged)

    # rehash_sim_data plans before it moves: two files of the same time whose new names are each other's old names both
    # survive; copies keep the old names; a file it can't read is reported and the rest is renamed
    set_save_path!(mktempdir())
    dir = joinpath(get_save_path(), "data")
    ph, pq = create_param_dict(:k => "hello"), create_param_dict(:k => "\"hello\"")
    fh = save_sim_data(review_data(ph, 10.0); verbose = false)
    fq = save_sim_data(review_data(pq, 20.0); verbose = false)
    stamp = "2026-01-01_00-00-00_000"
    a, b = joinpath(dir, "$(stamp)_$(calculate_hash(pq)).jld2"), joinpath(dir, "$(stamp)_$(calculate_hash(ph)).jld2")
    mv(fh, a); mv(fq, b)   # (each sits where the other belongs)
    PDEStudioCore._invalidate_index!()
    @test isnothing(PDEStudioCore._find_file(ph)) && isnothing(PDEStudioCore._find_file(pq))
    renamed = rehash_sim_data()
    @test sort(last.(renamed)) == sort([a, b]) && length(readdir(dir)) == 2
    @test load_sim_data(ph).u[1][1] == 10.0 && load_sim_data(pq).u[1][1] == 20.0
    mv(get_file_name(ph), joinpath(dir, "$(stamp)_$("0"^64).jld2"))   # (a wrong name, like a file of 0.7)
    PDEStudioCore._invalidate_index!()
    @test length(rehash_sim_data(; delete_old = false)) == 1 && length(readdir(dir)) == 3
    @test load_sim_data(ph).u[1][1] == 10.0 && isnothing(PDEStudioCore._find_file(create_param_dict(:k => "other")))
    rm(joinpath(dir, "$(stamp)_$("0"^64).jld2"))   # (the old copy)
    broken = joinpath(dir, "$(stamp)_$("1"^64).jld2")
    write(broken, "not a data file")
    mv(get_file_name(pq), joinpath(dir, "$(stamp)_$("2"^64).jld2"))
    PDEStudioCore._invalidate_index!()
    @test (@test_logs (:warn, r"not rehashed") match_mode = :any length(rehash_sim_data())) == 1
    @test isfile(broken) && load_sim_data(pq).u[1][1] == 20.0
    rm(broken)

    # a current file without its dataset is missing (the pipeline computes it again)
    pr = create_param_dict(:sim_func_name => :constant_solver, :case => :no_raw)
    run_all_simulations(SimulationConfig(pr))
    PDEStudioCore.JLD2.jldopen(f -> delete!(f, "raw"), get_file_name(pr), "a+")
    @test !does_sim_data_exist(pr)
    @test length(run_all_simulations(SimulationConfig(pr)).ran) == 1 && load_sim_data(pr).u[1][1] == 1.0

    # Float16 bounds whose difference overflows: the spacing in a wider type
    d16 = create_sim_data(SVector.(Float16[-40000, 0, 40000]), Float16[1, 2, 3], ParamDict())
    @test [v[1] for v in convert_to_eulerian(d16, (3,)).u] == Float16[1, 2, 3]
    set_save_path!(mktempdir())

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
    s = run_all_simulations(SimulationConfig(p))   # (an unreadable file isn't found: computed again, next to it)
    @test isempty(s.failed) && length(s.ran) == 1 && s.files[1] != file && isfile(file) && filesize(file) == 0

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

# Fixes of the A2 review of v0.6.3 (reviews/2026-11-23-v0.6.3-codex.md); the hash and folder cases are above (1)
review_ref_a(p) = x -> SVector(1.0)
review_ref_b(p) = x -> SVector(3.0)
my_error_doc(u, ana, w) = sum(map((v, a) -> abs.(v - a), u, ana) .* w)       # (docs/src/index.md)
custom_energy_doc(u, w) = sum(map(v -> abs2.(v), u) .* w)                     # (docs/src/statistics.md)

@testset "Review fixes (v0.6.3)" begin
    set_save_path!(mktempdir())

    # Float16 scatter: the geometry in a wider type (a squared radius of Float16 overflowed)
    d16 = create_sim_data(SVector.(Float16[1, 255]), Float16[1, 3], ParamDict(); xmins = 0, xmaxs = 256)
    @test [Float64(v[1]) for v in convert_to_eulerian(d16, (2,)).u] ≈ [1, 3] atol = 0.01

    # The record of the reference survives a call that evaluates nothing; another reference makes the values due
    p = create_param_dict(:sim_func_name => :constant_solver)
    cfg = SimulationConfig(p; reference = :review_ref_a)
    run_all_simulations(cfg; calculate_stats = true)
    calculate_all_stats!(load_sim_data(p))   # (nothing to evaluate: the record stays)
    cfg.reference = :review_ref_b
    s = run_all_simulations(cfg; calculate_stats = true)
    @test s.stats == Dict(:ran => 1) && load_sim_data(p).stats[:l1error][1] ≈ 4   # (|1 − 3| at two nodes of weight 1)
    calculate_all_stats!(load_sim_data(p), x -> SVector(1.0); force_overwrite = true)   # (unknown reference: due again)
    @test run_all_simulations(cfg; calculate_stats = true).stats == Dict(:ran => 1) && load_sim_data(p).stats[:l1error][1] ≈ 4   # (|1 − 3| at two nodes of weight 1)

    # A dataset keeps its own copy of the parameters (a later change of the caller's array doesn't move it)
    w = [1.0, 2.0]
    q = create_param_dict(:weights => w)
    dq = create_sim_data([0.0, 1.0], fill(3.0, 2), q)
    w[1] = 9.0
    save_sim_data(dq)
    @test does_sim_data_exist(create_param_dict(:weights => [1.0, 2.0])) && !does_sim_data_exist(q)

    # A save that is skipped (the native run is stored, no overwrite) leaves a derived dataset derived
    pn = create_param_dict(:case => :native_kept)
    save_sim_data(review_data(pn, 1.0))
    conv = convert_to_lagrangian(load_sim_data(pn))
    save_sim_data(conv)
    @test conv.metadata[:derived] === :conversion
    set_save_path!(mktempdir())
    @test_logs (:warn, r"not saved") match_mode = :any calculate_all_stats!(conv)
    @test !does_sim_data_exist(pn)

    # Zero duration: the initial snapshot alone (Lax–Friedrichs divided by a zero step)
    cb = test_burgers_1d()
    pb = merge(cb.shared, cb.methods[:lax_friedrichs], create_param_dict(:T => 0.0))
    db = PDEStudioCore.Examples.solve_burgers_1d(pb)
    @test db.axes[end] == [0.0] && all(v -> all(isfinite, v), db.u)
    @test_throws ArgumentError PDEStudioCore.Examples._time_grid(-1.0, 0.1)

    # The documented custom statistics work on vector-valued fields
    u2 = [SVector(1.0, -2.0), SVector(3.0, 4.0)]
    @test my_error_doc(u2, fill(SVector(0.0, 0.0), 2), 0.5) == SVector(2.0, 3.0)
    @test custom_energy_doc(u2, 0.5) == SVector(5.0, 10.0)
end
