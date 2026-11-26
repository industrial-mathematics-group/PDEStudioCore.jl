# The statistic layers (src/StatLayers.jl): simulation -> reference -> post-processing. Each statistic belongs to the
# layer that produced it; a layer is computed from the ones above it, so when they change it is evaluated again.
const LY_DATA_CALLS = Ref(0)
const LY_POST_SEEN = Ref{Vector{Symbol}}(Symbol[])
ly_solver(p) = (d = create_sim_data([0.0, 1.0], fill(Float64(p[:k]), 2), p); add_stat!(d, :ly_runtime, 3.0, Symbol[]); d)
ly_ref_a(p) = _ -> 2.0
ly_ref_b(p) = _ -> 4.0
PDEStudioCore.calc_stat(::Val{:ly_total}, fixed, u, domain) = (LY_DATA_CALLS[] += 1; sum(v -> v[1], u))   # (data alone)
PDEStudioCore.calc_stat(::Val{:ly_err}, fixed, u, ana, domain) = sum(i -> abs(u[i][1] - ana[i][1]), eachindex(u))
# post-processors: one derived from a statistic of each layer above, one of its own, and misbehaving ones
ly_weighted(d) = (push!(LY_POST_SEEN[], sort!(collect(keys(d.stats)))...);
                  add_stat!(d, :ly_weighted, d.stats[:ly_err][1][1] * d.stats[:ly_runtime][1][1], Symbol[]); true)
ly_other(d) = (add_stat!(d, :ly_other, 1.0, Symbol[]); true)
ly_touch(d) = (d.stats[:ly_runtime] = 99.0; true)            # (changes a statistic of the simulation layer)
ly_remove(d) = (delete!(d.stats, :ly_total); true)          # (removes one)
const LY_ADDS = Ref(true)
ly_maybe(d) = LY_ADDS[] ? (add_stat!(d, :ly_maybe, 1.0, Symbol[]); true) : false
ly_val(p, k) = (d = load_sim_data(p); haskey(d.stats, k) ? d.stats[k][1][1] : missing)
ly_weights_solver(p) = (d = create_sim_data(([0.0, 1.0], [0.0, 1.0]), ones(2, 2), p); add_stat!(d, :ly_weights, [2.0, 3.0], :x); d)
ly_weights_post(d) = (add_stat!(d, :ly_wsum, haskey(d.stats, :ly_weights) ? sum(first, d.stats[:ly_weights]) : -1.0, Symbol[]); true)
ly_reaxis(d) = (d.domain.stat_registry[:ly_weights] = :y; true)
ly_reshape(d) = (d.stats[:ly_weights] = reshape(d.stats[:ly_weights], 2, 1); true)
ly_failing_ref(p) = error("this reference can't be built")
# (writes its statistic of an earlier version again, with the same value; on a rerun its own statistic is set aside)
ly_same_post(d) = (d.stats[:ly_old_post] = haskey(d.stats, :ly_old_post) ? d.stats[:ly_old_post][1][1] : 4.0; true)
# (writes a statistic of the same name on another dataset, and adds one of its own to the run)
ly_elsewhere(d) = (scratch = create_sim_data([0.0, 1.0], [0.0, 0.0], ParamDict()); scratch.stats[:ly_runtime] = 99.0;
                   add_stat!(d, :ly_quality, 2.0, Symbol[]); true)
ly_first_post(d) = (add_stat!(d, :ly_first, 1.0, Symbol[]); true)
ly_assigning(d) = (s = copy(d.stats); delete!(s, :Solution); s[:ly_second] = SVector(2.0); d.stats = s; true)
ly_to_series(d) = (d.stats[:ly_runtime] = [first(d.stats[:ly_runtime])]; true)   # (a scalar made a one-element series)
ly_redim_other(d) = (d.domain.stat_registry[:ly_first] = :x; add_stat!(d, :ly_third, 1.0, Symbol[]); true)
PDEStudioCore.calc_stat(::Val{:__no_statistic__}, fixed, u, ana, domain) = 1.0   # (a statistic of any name may be implemented)
struct LyOtherDomain end
PDEStudioCore.calc_stat(::Val, fixed, u, domain::LyOtherDomain) = 0.0           # (generic, for another domain type)
PDEStudioCore.calc_stat(::Val{:ly_va}, fixed, u, rest...) = 1.0                 # (vararg: callable as a data statistic)
# a file as PDEStudioCore 0.9 wrote it: file format 3, the "evaluated_*" entries, no statistic records in the metadata
function ly_write_earlier(path, d)
    PDEStudioCore._write_sim_file(path, d, Dict{String, Any}("evaluated_stats" => [:ly_err, :ly_total],
                                  "evaluated_with_reference" => true), nothing)
    md = PDEStudioCore.JLD2.jldopen(f -> f["metadata"], path, "r")
    delete!(md, :stat_records)
    delete!(md, :postprocessed)
    PDEStudioCore._set_key!(path, "metadata", md)
    PDEStudioCore._set_key!(path, "format_version", 3)
end
ly_summary(d) = (d.metadata[:ly_summary] = d.stats[:ly_err][1][1]; true)   # (metadata only: records no statistic)
ly_scaled(d) = (add_stat!(d, :ly_scaled, 10.0 * d.params[:k], Symbol[]); true)   # (computed from the parameters)
ly_sneaky(d) = (d.stats[:ly_empty] = 0.5; true)              # (writes a registered name)
PDEStudioCore.calc_stat(::Val{:ly_empty}, fixed, u, ana, domain) = NaN   # (no result for this data)

@testset "Statistic layers" begin
    old = PDEStudioCore.get_stat_registry()
    try
        set_save_path!(mktempdir())
        set_stat_registry!(Dict(:ly_total => :time, :ly_err => :time))
        p = create_param_dict(:sim_func_name => :ly_solver, :k => 1)
        cfg(ref, post = :ly_weighted) = SimulationConfig(p; reference = ref, postprocess = post)

        # the layers, by what produced each statistic
        LY_DATA_CALLS[] = 0
        run_all_simulations(cfg(:ly_ref_a); calculate_stats = true)
        d = load_sim_data(p)
        @test layer_stats(d, :simulation) == [:Solution, :ly_runtime, :ly_total]
        @test layer_stats(d, :reference) == [:ly_err] && layer_stats(d, :postprocess) == [:ly_weighted]
        @test stat_layer(d, :ly_weighted) === :postprocess && d.stats[:ly_weighted][1][1] == 6.0   # (|1-2|·2 · 3)
        @test_throws KeyError stat_layer(d, :nope)
        @test_throws ArgumentError layer_stats(d, :other)
        calls = LY_DATA_CALLS[]

        # another reference: the reference layer is evaluated again, and the post-processing layer with it; the data
        # statistics stay (not evaluated again)
        s = run_all_simulations(cfg(:ly_ref_b); calculate_stats = true)
        @test s.stats == Dict(:ran => 1) && s.postprocessing == Dict(:ran => 1)
        @test ly_val(p, :ly_err) == 6.0 && ly_val(p, :ly_weighted) == 18.0 && LY_DATA_CALLS[] == calls
        s = run_all_simulations(cfg(:ly_ref_b); calculate_stats = true)
        @test s.stats == Dict(:cached => 1) && s.postprocessing == Dict(:skipped => 1)
        # without a reference the reference layer is left as it is (and so is what was computed from it)
        s = run_all_simulations(cfg(nothing); calculate_stats = true)
        @test s.stats == Dict(:cached => 1) && ly_val(p, :ly_err) == 6.0 && ly_val(p, :ly_weighted) == 18.0

        # a post-processor runs on the simulation and reference layers only: without its own earlier statistics and
        # without those of other post-processors, which stay
        run_all_simulations(cfg(:ly_ref_b, :ly_other))
        empty!(LY_POST_SEEN[])
        run_all_simulations(cfg(:ly_ref_b); force_postprocess = true)
        @test !(:ly_weighted in LY_POST_SEEN[]) && !(:ly_other in LY_POST_SEEN[]) && :ly_err in LY_POST_SEEN[]
        d = load_sim_data(p)
        @test layer_stats(d, :postprocess) == [:ly_other, :ly_weighted] && d.stats[:ly_weighted][1][1] == 18.0

        # it adds statistics of its own: changing or removing one of the layers above fails, nothing is saved
        for bad in (:ly_touch, :ly_remove)
            s = run_all_simulations(cfg(:ly_ref_b, bad))
            @test get(s.postprocessing, :failed, 0) == 1 && occursin("changed or removed", last(only(s.postprocessing_failed)))
        end
        @test ly_val(p, :ly_runtime) == 3.0 && ly_val(p, :ly_total) == 2.0
        # one that adds nothing this time loses what it added before
        LY_ADDS[] = true
        run_all_simulations(cfg(:ly_ref_b, :ly_maybe))
        LY_ADDS[] = false
        run_all_simulations(cfg(:ly_ref_b, :ly_maybe); force_postprocess = true)
        @test ismissing(ly_val(p, :ly_maybe)) && load_sim_data(p).metadata[:postprocessed][:ly_maybe][:keys] == Symbol[]

        # names are unique: registering the name of a post-processor's statistic makes the statistics pass fail
        register_stat!(:ly_other, :time)
        @eval PDEStudioCore.calc_stat(::Val{:ly_other}, fixed, u, domain) = 1.0
        s = run_all_simulations(cfg(:ly_ref_b); calculate_stats = true)
        @test get(s.stats, :failed, 0) == 1 && occursin("from the post-processor", last(only(s.stats_failed)))
        delete_stat!(:ly_other)

        # calculate_all_stats! with a reference function evaluates all reference statistics (it can't tell whether it
        # is the reference they were evaluated with); the post-processing layer goes
        d = load_sim_data(p)
        calculate_all_stats!(d, x -> 1.0; save = false)
        @test d.stats[:ly_err][1][1] == 0.0 && isempty(layer_stats(d, :postprocess)) && d.stats[:ly_total][1][1] == 2.0

        # data changed after its statistics were evaluated: saved, the statistics evaluated for the old solution go
        # (with their records), the solver's stay
        d = load_sim_data(p)
        d.u = [SVector(5.0), SVector(5.0)]
        save_sim_data(d; overwrite = true, verbose = false)
        d = load_sim_data(p)
        @test sort!(collect(keys(d.stats))) == [:Solution, :ly_runtime] && !haskey(d.metadata, :postprocessed)
        @test isempty(d.metadata[:stat_records][:simulation][:evaluated]) && !haskey(d.metadata[:stat_records], :reference)
        run_all_simulations(cfg(:ly_ref_a, nothing); calculate_stats = true)
        @test ly_val(p, :ly_total) == 10.0 && ly_val(p, :ly_err) == 6.0

        # a statistic whose calc_stat moves to the other layer leaves the record of the one it was in
        register_stat!(:ly_moving, :time)
        @eval PDEStudioCore.calc_stat(::Val{:ly_moving}, fixed, u, ana, domain) = 1.0
        run_all_simulations(cfg(:ly_ref_a, nothing); calculate_stats = true)
        @test stat_layer(load_sim_data(p), :ly_moving) === :reference
        Base.delete_method(which(PDEStudioCore.calc_stat, Tuple{Val{:ly_moving}, Any, Any, Any, Any}))
        @eval PDEStudioCore.calc_stat(::Val{:ly_moving}, fixed, u, domain) = 2.0
        run_all_simulations(cfg(nothing, nothing); calculate_stats = true)
        d = load_sim_data(p)
        @test stat_layer(d, :ly_moving) === :simulation && d.stats[:ly_moving][1][1] == 2.0
        @test !(:ly_moving in d.metadata[:stat_records][:reference][:evaluated])
        delete_stat!(:ly_moving)

        # a file of another format (an earlier one, 0.9; or a later one): no compatibility, not part of the store. It
        # isn't found, listed, loaded (also not by hash prefix), imported, post-processed or replaced (a save or a run
        # of its parameters is refused, the file stays byte for byte); tidy lists it as foreign
        set_save_path!(mktempdir())
        q = create_param_dict(:sim_func_name => :ly_solver, :k => 2)
        run_all_simulations(SimulationConfig(q; reference = :ly_ref_a); calculate_stats = true)
        path = get_file_name(q)
        loaded = load_sim_data(q)
        for format in (3, 5)
            ly_write_earlier(path, loaded)
            format == 5 && PDEStudioCore._set_key!(path, "format_version", 5)
            before = read(path)
            @test !does_sim_data_exist(q) && size(sim_data_table(), 1) == 0 && tidy_sim_data().foreign == [path]
            @test_throws SimFileNotFoundError load_sim_data(q)
            @test_throws r"version of PDEStudioCore \(file format \d; this version reads and writes format 4 only\)" load_sim_data(basename(path)[1:12])
            lc = SimulationConfig(q; reference = :ly_ref_b, postprocess = :ly_weighted)
            s = run_all_simulations(lc; calculate_stats = true)
            @test length(s.failed) == 1 && occursin("file of another format (file format $format", last(only(s.failed)))
            @test_throws r"file of another format" save_sim_data(loaded; overwrite = true, verbose = false)
            enable_cache!(true)
            @test_throws SimFileNotFoundError load_sim_data(q, :lagrangian)
            enable_cache!(false)
            moved = mktempdir()
            cp(path, joinpath(moved, "q.jld2"))
            store = dirname(dirname(path))
            set_save_path!(mktempdir())
            @test isempty(import_sim_data(moved))
            set_save_path!(store)
            @test read(path) == before   # (untouched)
        end
        # (moved away, the run is computed again in format 4)
        mv(path, joinpath(mktempdir(), "old.jld2"))
        run_all_simulations(SimulationConfig(q; reference = :ly_ref_b, postprocess = :ly_weighted); calculate_stats = true)
        @test PDEStudioCore._file_format(path) == 4 && ly_val(q, :ly_err) == 4.0 && ly_val(q, :ly_weighted) == 12.0

        # a post-processor whose code changed: :warn keeps its statistics (outdated), :recompute runs it again
        set_save_path!(mktempdir())
        src = joinpath(mktempdir(), "post.jl")
        write(src, "ly_src_post(d) = (add_stat!(d, :ly_src, 1.0, Symbol[]); true)\n")
        sc = SimulationConfig(create_param_dict(:sim_func_name => :ly_solver, :k => 3); postprocess = :ly_src_post, sources = [src])
        run_all_simulations(sc)
        write(src, "ly_src_post(d) = (add_stat!(d, :ly_src, 2.0, Symbol[]); true)\n")
        @test run_all_simulations(sc).postprocessing == Dict(:outdated => 1)
        @test run_all_simulations(sc; on_changed_sources = :recompute).postprocessing == Dict(:ran => 1)
        @test ly_val(only(generate_tasks(sc)), :ly_src) == 2.0

        # hunt on the layers (2026-11-25): a post-processor that records no statistics (metadata only) runs again when
        # the reference changes (its record isn't brought back from the file), also in a dry run
        set_save_path!(mktempdir())
        r = create_param_dict(:sim_func_name => :ly_solver, :k => 1)
        mc(ref) = SimulationConfig(r; reference = ref, postprocess = :ly_summary)
        run_all_simulations(mc(:ly_ref_a); calculate_stats = true)
        @test load_sim_data(r).metadata[:ly_summary] == 2.0
        @test run_all_simulations(mc(:ly_ref_b); calculate_stats = true, dry_run = true).postprocessing == Dict(:ran => 1)
        @test run_all_simulations(mc(:ly_ref_b); calculate_stats = true).postprocessing == Dict(:ran => 1)
        @test load_sim_data(r).metadata[:ly_summary] == 6.0
        # statistics added to the layers above are a new state for the post-processors too
        set_save_path!(mktempdir())
        run_all_simulations(mc(:ly_ref_a, ))   # (post-processed before any statistics: fails, no :ly_err yet)
        s = run_all_simulations(mc(:ly_ref_a); calculate_stats = true)
        @test s.postprocessing == Dict(:ran => 1) && load_sim_data(r).metadata[:ly_summary] == 2.0

        # saved under other parameters, the reference and post-processing layers go (they were computed with the
        # parameters); the statistics of the data alone stay
        set_save_path!(mktempdir())
        sc2 = SimulationConfig(r; reference = :ly_ref_a, postprocess = :ly_scaled)
        run_all_simulations(sc2; calculate_stats = true)
        d = load_sim_data(r)
        d.params[:k] = 7
        save_sim_data(d; verbose = false)
        r7 = create_param_dict(:sim_func_name => :ly_solver, :k => 7)
        @test sort!(collect(keys(load_sim_data(r7).stats))) == [:Solution, :ly_runtime, :ly_total]
        @test run_all_simulations(SimulationConfig(r7; reference = :ly_ref_a, postprocess = :ly_scaled); calculate_stats = true).postprocessing == Dict(:ran => 1)
        @test ly_val(r7, :ly_scaled) == 70.0

        # a post-processor can't write a registered name, also one without a value (all NaN)
        register_stat!(:ly_empty, :time)
        s = run_all_simulations(SimulationConfig(r; reference = :ly_ref_a, postprocess = :ly_sneaky); calculate_stats = true)
        @test get(s.postprocessing, :failed, 0) == 1 && occursin("is registered", last(only(s.postprocessing_failed)))
        delete_stat!(:ly_empty)

        # review of 0.10: a statistic of the solver removed (or replaced by hand) and saved: the post-processor that
        # computed from it runs again (its record holds the layers above it ran on)
        set_save_path!(mktempdir())
        w = create_param_dict(:sim_func_name => :ly_weights_solver)
        wc = SimulationConfig(w; postprocess = :ly_weights_post)
        run_all_simulations(wc)
        @test ly_val(w, :ly_wsum) == 5.0
        d = load_sim_data(w)
        delete_stat!(d, :ly_weights)
        save_sim_data(d; overwrite = true, verbose = false)
        @test run_all_simulations(wc).postprocessing == Dict(:ran => 1) && ly_val(w, :ly_wsum) == -1.0
        d = load_sim_data(w)
        add_stat!(d, :ly_weights, [10.0, 20.0], :x)
        save_sim_data(d; overwrite = true, verbose = false)
        @test run_all_simulations(wc).postprocessing == Dict(:ran => 1) && ly_val(w, :ly_wsum) == 30.0
        # ... and a post-processor can't change the kept dimensions or the shape of a statistic above
        for bad in (:ly_reaxis, :ly_reshape)
            s = run_all_simulations(SimulationConfig(w; postprocess = bad))
            @test get(s.postprocessing, :failed, 0) == 1
        end
        d = load_sim_data(w)
        @test get_kept_dims(:ly_weights, d.domain) == [:x] && size(d.stats[:ly_weights]) == (2,)

        # calculate_all_stats! returns the dataset; a registered name without any calc_stat fails, also without a
        # reference; a reference factory is only built when reference statistics are due
        d = load_sim_data(w)
        @test calculate_all_stats!(d; save = false) === d
        register_stat!(:ly_typo, :time)
        s = run_all_simulations(SimulationConfig(w); calculate_stats = true)
        @test get(s.stats, :failed, 0) == 1 && occursin("has no `calc_stat` method", last(only(s.stats_failed)))
        delete_stat!(:ly_typo)
        set_stat_registry!(Dict(:ly_total => :time))
        s = run_all_simulations(SimulationConfig(w; reference = :ly_failing_ref); calculate_stats = true)
        @test s.stats == Dict(:ran => 1) && ly_val(w, :ly_total) == 4.0   # (2×2 ones, no time axis)

        # an import with removed keys keeps the run's records valid under its new parameters; a reference factory is
        # built when the loaded data needs one
        set_save_path!(mktempdir())
        set_stat_registry!(Dict(:ly_total => :time, :ly_err => :time))
        a = create_param_dict(:sim_func_name => :ly_solver, :k => 1, :obsolete => "x")
        run_all_simulations(SimulationConfig(a; reference = :ly_ref_a, postprocess = :ly_weighted); calculate_stats = true)
        moved = mktempdir()
        mv(get_file_name(a), joinpath(moved, "a.jld2"))
        import_sim_data(moved; remove_keys = [:obsolete])
        ic = SimulationConfig(p; reference = :ly_ref_a, postprocess = :ly_weighted)
        s = run_all_simulations(ic; calculate_stats = true)
        @test s.stats == Dict(:cached => 1) && s.postprocessing == Dict(:skipped => 1)
        d = load_sim_data(p)
        save_sim_data(d; overwrite = true, verbose = false)
        @test layer_stats(load_sim_data(p), :reference) == [:ly_err]

        # the kind of a statistic: by the calls the statistics pass makes
        @test PDEStudioCore._stat_kind(:ly_va) === :data && PDEStudioCore._stat_kind(:ly_err) === :reference
        @test PDEStudioCore._stat_kind(:ly_unknown_name) === :none

        # L2: rescaled per component where the squares overflow or underflow, the measure factored out
        l2(u, m) = PDEStudioCore._wide_l2(v -> abs.(v), m, u)
        @test l2([SVector(1e200, NaN), SVector(1e200, 1.0)], 1.0)[1] ≈ sqrt(2) * 1e200
        @test l2([SVector(1e-200), SVector(1e-200)], 1.0)[1] ≈ sqrt(2) * 1e-200
        @test l2([SVector(1.0), SVector(1.0)], 1e308)[1] ≈ sqrt(2.0) * sqrt(1e308)
        @test l2([SVector(1.0, 2.0), SVector(3.0, 4.0)], 0.5) == sqrt.(SVector(10.0, 20.0) .* 0.5)   # (bit-identical)

        # a post-processor that assigns `data.stats` keeps the other post-processors' statistics; a scalar made a
        # series is a change
        set_save_path!(mktempdir())
        run_all_simulations(SimulationConfig(p; postprocess = :ly_first_post))
        run_all_simulations(SimulationConfig(p; postprocess = :ly_assigning))
        d = load_sim_data(p)
        @test layer_stats(d, :postprocess) == [:ly_first, :ly_second]
        s = run_all_simulations(SimulationConfig(p; postprocess = :ly_to_series))
        @test get(s.postprocessing, :failed, 0) == 1 && ly_val(p, :ly_runtime) == 3.0

        # the generic fallback isn't confused with a statistic of any name
        register_stat!(:__no_statistic__, :time)
        @test PDEStudioCore._stat_kind(:__no_statistic__) === :reference
        delete_stat!(:__no_statistic__)

        # L2: a measure (or a partial product of it) outside the range of normal floats is refused; an undefined
        # (NaN) value makes its component NaN, also where the others are zero; a subnormal sum is scaled
        set_stat_registry!(Dict(:l2norm => Symbol[]))
        for spacing in (1e200, 1e-200)
            d = create_sim_data(([0.0, spacing], [0.0, spacing]), ones(2, 2), ParamDict())
            @test_throws r"integration measure of :l2norm" calculate_all_stats!(d; save = false)
        end
        d = create_sim_data(([0.0, 2e-162], [0.0, 2e-162], [0.0, 1e308]), ones(2, 2, 2), ParamDict())   # (normal product, subnormal partial)
        @test_throws r"partial products" calculate_all_stats!(d; save = false)
        l2(u) = PDEStudioCore._wide_l2(v -> abs.(v), 1.0, u)
        @test isequal(l2([SVector(0.0, 1.0), SVector(NaN, 2.0)]), SVector(NaN, sqrt(5.0)))
        @test l2([SVector(0.0, 0.0), SVector(0.0, 0.0)]) == SVector(0.0, 0.0)
        @test PDEStudioCore._wide_l2(v -> abs.(v), 2e-300, fill(SVector(1.4e-174), 4))[1] == 5e-324   # (not a spurious 0)
        tiny = sqrt(nextfloat(0.0)) * sqrt(0.51)
        d = create_sim_data([0.0], [tiny], ParamDict())
        calculate_all_stats!(d; save = false)
        @test only(d.stats[:l2norm])[1] ≈ Float64(sqrt(big(tiny)^2)) rtol = 1e-12

        # focused hunt on the a4089e3 fixes: a statistic's fingerprint doesn't depend on the names a session imported;
        # another post-processor's kept dimensions are restored; L2 of zero data with an infinite measure is 0, and a
        # subnormal measure doesn't cost precision beyond the log path
        @test PDEStudioCore._kind_text(SVector(1.0)) == "s1Float64" && PDEStudioCore._kind_text([SVector(1.0)]) == "a1[s1Float64]"
        set_save_path!(mktempdir())
        run_all_simulations(SimulationConfig(p; postprocess = :ly_first_post))
        run_all_simulations(SimulationConfig(p; postprocess = :ly_redim_other))
        @test get_kept_dims(:ly_first, load_sim_data(p).domain) == Symbol[]
        @test run_all_simulations(SimulationConfig(p; postprocess = :ly_first_post)).postprocessing == Dict(:skipped => 1)
        set_stat_registry!(Dict(:l2norm => Symbol[]))
        d = create_sim_data(([0.0, 0.5], [0.0, 0.5]), zeros(2, 2), ParamDict())
        calculate_all_stats!(d; save = false)
        @test only(d.stats[:l2norm])[1] == 0.0
        d = create_sim_data(([0.0, 1e-160], [0.0, 1e-160]), ones(2, 2), ParamDict())   # (a subnormal measure: refused)
        @test_throws r"integration measure" calculate_all_stats!(d; save = false)
    finally
        set_stat_registry!(old)
    end
end
