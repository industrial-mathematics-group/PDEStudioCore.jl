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
ly_legacy_post(d) = (d.stats[:ly_old_post] = 5.0; true)     # (rewrites the statistic it added in an earlier version)
ly_val(p, k) = (d = load_sim_data(p); haskey(d.stats, k) ? d.stats[k][1][1] : missing)

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
        @test sort!(collect(keys(d.stats))) == [:Solution, :ly_runtime] && !haskey(d.metadata, :stat_records)
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

        # a file of an earlier version: its records ("evaluated_*" entries) are read as this version's, and a
        # statistic its post-processor added becomes the post-processor's when it runs again and rewrites it
        set_save_path!(mktempdir())
        q = create_param_dict(:sim_func_name => :ly_solver, :k => 2)
        run_all_simulations(SimulationConfig(q; reference = :ly_ref_a); calculate_stats = true)
        path = get_file_name(q)
        JLD2 = PDEStudioCore.JLD2
        old_md, record = JLD2.jldopen(f -> (PDEStudioCore._file_metadata(f), f["metadata"][:stat_records][:reference][:record]), path, "r")
        d = load_sim_data(q)
        d.stats[:ly_old_post] = 4.0                              # (what its post-processor added then)
        delete!(d.metadata, :stat_records)
        d.metadata[:postprocessed] = Dict(:ly_legacy_post => Dict{Symbol, Any}(:sources => String[]))
        PDEStudioCore._write_sim_file(path, d, Dict{String, Any}("evaluated_stats" => [:ly_err, :ly_total],
                                      "evaluated_with_reference" => true, "evaluated_reference" => record), nothing)
        d = load_sim_data(q)
        @test stat_layer(d, :ly_err) === :reference && stat_layer(d, :ly_total) === :simulation
        @test stat_layer(d, :ly_old_post) === :simulation && :ly_old_post in d.metadata[:stat_records][:legacy]
        lc = SimulationConfig(q; reference = :ly_ref_a, postprocess = :ly_legacy_post)
        s = run_all_simulations(lc; calculate_stats = true)
        @test s.stats == Dict(:cached => 1) && s.postprocessing == Dict(:skipped => 1)   # (same reference, same record)
        run_all_simulations(lc; force_postprocess = true)
        d = load_sim_data(q)
        @test stat_layer(d, :ly_old_post) === :postprocess && d.stats[:ly_old_post][1][1] == 5.0
        @test !JLD2.jldopen(f -> haskey(f, "evaluated_stats"), path, "r")   # (written again: the old entries go)

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
    finally
        set_stat_registry!(old)
    end
end
