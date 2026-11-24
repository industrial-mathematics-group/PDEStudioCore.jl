# Fixes of the A2 reviews of the hash format 3 (reviews/2026-11-23-hash-format-3-codex.md) and of v0.7.1
# (reviews/2026-11-23-v0.7.1-codex.md), one case per finding. Since 0.8 the store keeps one file per run under its
# hash and never moves or deletes data on its own; the cases check that what the findings lost is kept.
h3_params(v) = create_param_dict(:k => v)
h3_data(p, v) = create_sim_data([0.0, 1.0], fill(Float64(v), 2), p)
h3_save(p, v; kw...) = save_sim_data(h3_data(p, v); verbose = false, kw...)
h3_stored(path) = PDEStudioCore.JLD2.jldopen(f -> (f["params"][:k], f["raw"].u[1][1]), path, "r")
h3_fresh() = (root = mktempdir(); set_save_path!(root); joinpath(root, "data"))
h3_name(p) = PDEStudioCore._hash_path(calculate_hash(p))
h3_snapshot(dir) = Dict(relpath(joinpath(r, f), dir) => (islink(joinpath(r, f)) ? readlink(joinpath(r, f)) : read(joinpath(r, f)))
                        for (r, _, fs) in walkdir(dir) for f in fs)

@testset "Review fixes (hash format 3)" begin
    @testset "1. a file replaced with its modification time kept is read again" begin
        h3_fresh()
        a = h3_save(h3_params("A"), 10)
        b = h3_save(h3_params("B"), 20)
        Sys.islinux() && run(`touch -r $a $b`)                     # (the replacement keeps the time)
        @test get_file_name(h3_params("A")) == a                   # (warms the cache)
        mv(b, a; force = true)
        @test h3_stored(a) == ("B", 20.0) && !does_sim_data_exist(h3_params("A"))
        @test_throws r"other parameters" h3_save(h3_params("A"), 30; overwrite = true)
        @test h3_stored(a) == ("B", 20.0)                          # B is not replaced by A
    end

    @testset "2. true is not 1 when a stored file is checked" begin
        h3_fresh()
        b = h3_save(h3_params(true), 20)
        a = h3_name(h3_params(1))
        mv(b, a)
        @test calculate_hash(h3_params(true)) != calculate_hash(h3_params(1))
        @test isnothing(PDEStudioCore._find_file(h3_params(1)))
        @test_throws r"other parameters" h3_save(h3_params(1), 30; overwrite = true)
        @test h3_stored(a) == (true, 20.0)
    end

    @testset "3. long names are imported, the source is only read" begin
        dir = h3_fresh()
        src = mktempdir()
        short = joinpath(src, "a_" * "0"^64 * ".jld2")
        long = joinpath(src, "z"^182 * "_" * "1"^64 * ".jld2")   # 252 bytes: legal, no room for a suffix
        mv(h3_save(h3_params("short"), 1), short)
        mv(h3_save(h3_params("long"), 2), long)
        before = h3_snapshot(src)
        @test length(import_sim_data(src)) == 2 && h3_snapshot(src) == before
        @test !any(f -> endswith(f, ".tmp"), readdir(dir))
        @test h3_stored(get_file_name(h3_params("short"))) == ("short", 1.0)
        @test h3_stored(get_file_name(h3_params("long"))) == ("long", 2.0)
    end

    if Sys.isunix()
        @testset "4. a link next to its target: one run, the source unchanged" begin
            h3_fresh()
            src = mktempdir()
            both = create_param_dict(:k => "target", :obsolete => 1)
            target = joinpath(src, "z_" * calculate_hash(both) * ".jld2")
            mv(h3_save(both, 20), target)
            symlink(basename(target), joinpath(src, "a_" * calculate_hash(both) * ".jld2"))
            before = h3_snapshot(src)
            imported = @test_logs (:warn, r"imported before") match_mode = :any import_sim_data(src; remove_keys = [:obsolete])
            @test length(imported) == 1 && h3_snapshot(src) == before
            @test h3_stored(get_file_name(h3_params("target"))) == ("target", 20.0)
        end
    end

    @testset "5. tidy never deletes data" begin
        dir = h3_fresh()
        original = h3_save(h3_params("A"), 10)
        wrong = joinpath(dir, "z_" * calculate_hash(h3_params("A")) * ".jld2")
        mv(h3_save(h3_params("B"), 20), wrong)
        Sys.islinux() && run(`touch -r $original $wrong`)
        result = tidy_sim_data()
        @test result.foreign == [wrong] && isempty(result.temp_files) && isfile(original) && isfile(wrong)
        @test h3_stored(get_file_name(h3_params("A"))) == ("A", 10.0)
        @test !does_sim_data_exist(h3_params("B"))                 # (B is under another name: import it)
        @test only(import_sim_data(wrong)) == (wrong => h3_name(h3_params("B"))) && h3_stored(get_file_name(h3_params("B"))) == ("B", 20.0)
    end

    @testset "6. integer and Float16 particle domains" begin
        d = DomainInfo{1, Int}((:x,), (0,), (1,), (1,), nothing)
        particles = LSimData(ParamDict(), d, [0], [[SVector(0), SVector(1)]], [[SVector(2), SVector(2)]])
        @test first.(convert_to_eulerian(particles, (2,)).u) == [2, 2]
        x16 = [SVector(Float16(-40000)), SVector(Float16(40000))]                 # static particles
        p16 = create_sim_data(x16, [SVector(Float16(0.25)), SVector(Float16(0.25))], ParamDict())
        @test p16.domain.spacing[1] == Float16(40000)
    end

    @testset "7. the parameter cache is bounded" begin
        cache = PDEStudioCore._STORED_IDENTITY
        for n in 1:4
            h3_fresh()
            q = h3_params(string(n) * repeat("x", 4096))
            h3_save(q, n)
            get_file_name(q)
            delete_sim_data(q)
        end
        @test length(cache) <= PDEStudioCore._STORED_MAX
        foreach(i -> (cache["/nonexistent/$i"] = ((UInt(0), 0, 0.0), nothing)), 1:PDEStudioCore._STORED_MAX)
        h3_fresh()
        h3_save(h3_params("after"), 1)
        get_file_name(h3_params("after"))
        @test length(cache) < 10
    end
end

@testset "Review fixes (v0.7.1)" begin
    @testset "1. tidy keeps the only complete run next to a partial copy" begin
        dir = h3_fresh()
        q = h3_params("seven")
        complete = h3_save(q, 7)
        partial = joinpath(dir, "1"^64 * ".jld2")   # (under another hash, without its dataset)
        cp(complete, partial)
        PDEStudioCore.JLD2.jldopen(f -> delete!(f, "raw"), partial, "a+")
        Sys.islinux() && run(`touch -d "2020-01-01" $complete`)   # (the complete file is older)
        result = tidy_sim_data()
        @test result.foreign == [partial] && isfile(complete) && isfile(partial)
        @test does_sim_data_exist(q) && load_sim_data(q).u[1][1] == 7.0
    end

    if Sys.isunix()
        @testset "2. a filtered import changes no link" begin
            h3_fresh()
            src = mktempdir()
            target = joinpath(src, "run.jld2")
            mv(h3_save(h3_params("run"), 1), target)
            symlink(basename(target), joinpath(src, "link.jld2"))
            before = h3_snapshot(src)
            @test isempty(import_sim_data(src; filter_pairs = Dict(:k => "unmatched"))) && h3_snapshot(src) == before
        end
    end

    @testset "3. an import moves nothing next to its source" begin
        dir = h3_fresh()
        file = h3_save(h3_params("placed"), 3)
        mkpath(joinpath(dir, ".rehash-backup"))
        write(joinpath(dir, ".rehash-backup", "notes.txt"), "mine")
        before = h3_snapshot(dir)
        @test isempty(import_sim_data(file)) && h3_snapshot(dir) == before
        @test isempty(import_sim_data(dir)) && h3_snapshot(dir) == before
    end

    @testset "4. an interrupted import leaves at most a temporary file; the retry imports" begin
        dir = h3_fresh()
        src = mktempdir()
        old = joinpath(src, "2026-01-01_00-00-00_000_" * "2"^64 * ".jld2")
        mv(h3_save(h3_params("only"), 4), old)
        tmp = PDEStudioCore._tmp_path(h3_name(h3_params("only")))   # (a copy killed halfway)
        write(tmp, "half a file")
        @test !does_sim_data_exist(h3_params("only")) && isempty(find_sim_data(; verbose = false))
        @test length(import_sim_data(src)) == 1 && h3_stored(get_file_name(h3_params("only"))) == ("only", 4.0)
        @test tidy_sim_data(min_tmp_age = 0).temp_files == [tmp] && !ispath(tmp) && isfile(old)
    end

    if Sys.isunix()
        @testset "5. a relative link to a file outside is read through" begin
            h3_fresh()
            outer = mktempdir()
            shared = joinpath(outer, "shared.jld2")
            mv(h3_save(create_param_dict(:k => "shared", :obsolete => 1), 5), shared)
            mkpath(joinpath(outer, "runs"))
            symlink(joinpath("..", "shared.jld2"), joinpath(outer, "runs", "link.jld2"))
            before = h3_snapshot(outer)
            @test length(import_sim_data(joinpath(outer, "runs"); remove_keys = [:obsolete])) == 1
            @test h3_stored(get_file_name(h3_params("shared"))) == ("shared", 5.0) && h3_snapshot(outer) == before
        end
    end
end

# Fixes of the A2 review of #34 (reviews/2026-11-23-one-file-store-codex.md), one case per finding
@testset "Review fixes (one-file store)" begin
    h3_corrupt!(path) = PDEStudioCore.JLD2.jldopen(f -> (delete!(f, "raw"); f["raw"] = "not a simulation dataset"), path, "a+")

    @testset "1. a file without a dataset is never imported" begin
        h3_fresh()
        p = h3_params("run")
        good = h3_save(p, 7)
        original = read(good)
        bad = joinpath(mktempdir(), "bad.jld2")
        cp(good, bad)
        h3_corrupt!(bad)
        @test isempty(@test_logs (:warn, r"no dataset") match_mode = :any import_sim_data(bad; overwrite = true))
        @test read(good) == original && load_sim_data(p) isa ESimData
        # nor a dataset of other parameters than its file says
        other = joinpath(mktempdir(), "other.jld2")
        cp(good, other)
        PDEStudioCore.JLD2.jldopen(f -> (delete!(f, "params"); f["params"] = h3_params("else")), other, "a+")
        @test isempty(@test_logs (:warn, r"other parameters than the file") match_mode = :any import_sim_data(other))
        @test !does_sim_data_exist(h3_params("else"))
    end

    if Sys.isunix()
        @testset "2. a linked destination is neither written through nor replaced" begin
            h3_fresh()
            p = h3_params("run")
            dest = h3_save(p, 7)
            external = joinpath(mktempdir(), "external.jld2")
            mv(dest, external)
            symlink(external, dest)
            src = h3_save(create_param_dict(:k => "run", :obsolete => true), 9)
            before = read(external)
            @test isempty(@test_logs (:warn, r"symbolic link") match_mode = :any import_sim_data(src; remove_keys = [:obsolete], overwrite = true))
            @test islink(dest) && read(external) == before
        end
    end

    @testset "3. an import never writes one of its own source files" begin
        dir = h3_fresh()
        p = h3_params("run")
        dest = h3_save(p, 7)
        candidate = joinpath(dir, "000-incoming.jld2")
        mv(h3_save(create_param_dict(:k => "run", :obsolete => true), 9), candidate)
        before = read(dest)
        @test isempty(@test_logs (:warn, r"files this import reads") match_mode = :any import_sim_data(dir; remove_keys = [:obsolete], overwrite = true))
        @test read(dest) == before && h3_stored(dest) == ("run", 7.0)
        # from elsewhere, `overwrite` replaces it
        outside = joinpath(mktempdir(), "incoming.jld2")
        cp(candidate, outside)
        @test only(import_sim_data(outside; remove_keys = [:obsolete], overwrite = true)) == (outside => dest)
        @test h3_stored(dest) == ("run", 9.0)
    end

    @testset "4. a retry replaces an incomplete destination" begin
        h3_fresh()
        p = h3_params("retry")
        dest = h3_save(p, 7)
        good = joinpath(mktempdir(), "good.jld2")
        cp(dest, good)
        PDEStudioCore.JLD2.jldopen(f -> delete!(f, "raw"), dest, "a+")
        @test !does_sim_data_exist(p)
        @test (@test_logs (:info, r"isn't a usable run") match_mode = :any length(import_sim_data(good))) == 1
        @test does_sim_data_exist(p) && h3_stored(dest) == ("retry", 7.0)
    end

    @testset "5 (and outside #34). filters tell 1 from true and 1.0" begin
        h3_fresh()
        a, b, c = h3_save(h3_params(1), 7), h3_save(h3_params(true), 9), h3_save(h3_params(1.0), 8)
        @test find_sim_data(Dict(:k => 1); verbose = false) == [a]
        @test delete_sim_data(Dict(:k => 1); dry_run = true) == [a]
        @test find_sim_data(Dict(:k => true); verbose = false) == [b] && find_sim_data(Dict("k" => 1.0); verbose = false) == [c]
        @test size(sim_data_table(Dict(:k => 1)), 1) == 1
        src = mktempdir()
        foreach(f -> cp(f, joinpath(src, basename(f))), (a, b, c))
        h3_fresh()
        @test last.(import_sim_data(src; filter_pairs = Dict(:k => 1))) == [h3_name(h3_params(1))]
        @test delete_sim_data(Dict(:k => 1)) == [h3_name(h3_params(1))] && isempty(find_sim_data(; verbose = false))
    end

    if Sys.isunix()
        @testset "6. a dangling link at a run's name is never replaced" begin
            h3_fresh()
            p = h3_params("run")
            dest = h3_name(p)
            mkpath(dirname(dest))
            missing_target = joinpath(get_save_path(), "separate-mount.jld2")
            symlink(missing_target, dest)
            @test_throws r"symbolic link whose target is missing" h3_save(p, 7)
            @test islink(dest) && !ispath(missing_target)
            @test_throws r"symbolic link whose target is missing" h3_save(p, 7; overwrite = true)
            @test islink(dest)
        end
    end
end

# Fixes of the A2 review of 0.8.0 (reviews/2026-11-23-v0.8.0-codex.md), one case per finding
const H3_SWAP = Ref{Tuple{String, String}}()
h3_swap_during_prompt() = (mv(H3_SWAP[][2], H3_SWAP[][1]; force = true); "other")   # (called from the prompt below)

@testset "Review fixes (v0.8.0)" begin
    @testset "1. a source changed after its check is reported, not installed" begin
        h3_fresh()
        p = h3_params("run")
        dest = h3_save(p, 7)
        original = read(dest)
        folder = mktempdir()
        src = joinpath(folder, "a-incoming.jld2")
        cp(h3_save(h3_params("other"), 11), joinpath(folder, "z-next.jld2"))
        replacement = joinpath(mktempdir(), "replacement.jld2")
        cp(dest, src); cp(dest, replacement)
        PDEStudioCore.JLD2.jldopen(f -> (delete!(f, "raw"); f["raw"] = "unusable replacement"), replacement, "a+")
        H3_SWAP[] = (src, replacement)
        imported = mktemp() do path, io   # (the first prompt keeps `k`, the second replaces the first source)
            write(io, "\nh3_swap_during_prompt()\n"); flush(io); seekstart(io)
            redirect_stdout(devnull) do
                redirect_stdin(io) do
                    @test_logs (:warn, r"changed since it was checked") match_mode = :any import_sim_data(folder; prompt_keys = [:k], overwrite = true)
                end
            end
        end
        @test length(imported) == 1 && read(dest) == original && load_sim_data(p) isa ESimData
        @test !any(f -> endswith(f, ".tmp"), readdir(dirname(dest)))
        # a changed source with a parameter change isn't rewritten either
        h3_fresh()
        src2 = joinpath(mktempdir(), "run.jld2")
        mv(h3_save(create_param_dict(:k => "run", :obsolete => 1), 5), src2)
        H3_SWAP[] = (src2, replacement)
        cp(dest, replacement; force = true)
        PDEStudioCore.JLD2.jldopen(f -> (delete!(f, "raw"); f["raw"] = "unusable replacement"), replacement, "a+")
        mktemp() do path, io
            write(io, "h3_swap_during_prompt()\n"); flush(io); seekstart(io)
            redirect_stdout(devnull) do
                redirect_stdin(io) do
                    @test isempty(import_sim_data(src2; prompt_keys = [:obsolete], remove_keys = [:obsolete]))
                end
            end
        end
        @test isempty(find_sim_data(; verbose = false))
    end

    @testset "2. a filter excludes a run before its dataset is read" begin
        h3_fresh()
        broken = joinpath(mktempdir(), "broken.jld2")
        cp(h3_save(h3_params("run"), 1), broken)
        PDEStudioCore.JLD2.jldopen(f -> (delete!(f, "raw"); f["raw"] = "no dataset"), broken, "a+")
        @test isempty(@test_logs min_level = Base.CoreLogging.Warn import_sim_data(broken; filter_pairs = Dict(:k => "unmatched")))
        @test isempty(@test_logs (:warn, r"no dataset") match_mode = :any import_sim_data(broken; filter_pairs = Dict(:k => "run")))
    end

    if Sys.isunix()
        @testset "3. a save follows a link at the run's name (as documented)" begin
            h3_fresh()
            p = h3_params("run")
            dest = h3_save(p, 7)
            external = joinpath(mktempdir(), "shared.jld2")
            mv(dest, external); symlink(external, dest)
            h3_save(p, 9; overwrite = true)
            @test islink(dest) && h3_stored(external) == ("run", 9.0)
        end
    end
end

# Fixes of the reviews of 2026-11-24 (reviews/2026-11-24-full-codebase-codex.md) and of #39
# (reviews/2026-11-23-checked-import-codex.md), one case per finding
struct H3Calibration
    value::Int
end
const H3_WRITE = Ref(true)   # (a type whose stored form reads, but can't be written in this session)
PDEStudioCore.JLD2.writeas(::Type{H3Calibration}) = Int
PDEStudioCore.JLD2.wconvert(::Type{Int}, x::H3Calibration) = H3_WRITE[] ? x.value : error("calibration writer unavailable")
PDEStudioCore.JLD2.rconvert(::Type{H3Calibration}, x::Int) = H3Calibration(x)
h3_case(k) = create_param_dict(:sim_func_name => :h3_solver, :k => k)
h3_solver(p) = create_sim_data([0.0, 1.0], fill(Float64(p[:k]), 2), p)
h3_reference(p) = _ -> p[:k]
h3_moving_post(data) = (data.params[:k] = 2; true)
h3_diag(k) = create_param_dict(:sim_func_name => :h3_diag_solver, :k => k)
h3_diag_solver(p) = (d = h3_solver(p); add_stat!(d, :iterations, 23.0, Symbol[]); d)   # (a solver diagnostic)
h3_double_reference(p) = _ -> 2 * p[:k]
h3_add_one(data) = (data.u = map(v -> v .+ 1, data.u); true)

@testset "Review fixes (2026-11-24)" begin
    @testset "1. an entry that can't be carried over fails the rewrite, the file stays" begin
        h3_fresh()
        p = h3_params("calibrated")
        data = h3_data(p, 1)
        path = save_sim_data(data; verbose = false)
        PDEStudioCore.JLD2.jldopen(f -> (f["calibration"] = H3Calibration(47)), path, "a+")
        before = read(path)
        H3_WRITE[] = false
        data.metadata[:units] = "K"
        try
            @test_throws r"entry 'calibration'.*can't be carried over"s save_sim_data(data; overwrite = true, verbose = false)
        finally
            H3_WRITE[] = true
        end
        @test read(path) == before && !any(f -> endswith(f, ".tmp"), readdir(dirname(path)))
        @test PDEStudioCore.JLD2.jldopen(f -> f["calibration"].value, path, "r") == 47
    end

    @testset "2. a post-processor that changes the parameters fails, no run is replaced" begin
        h3_fresh()
        a, b = h3_case(1), h3_case(2)
        save_sim_data(h3_solver(b); verbose = false)
        s = run_all_simulations(SimulationConfig(a; postprocess = :h3_moving_post))
        @test s.postprocessing[:failed] == 1 && occursin("changed the parameters", last(only(s.postprocessing_failed)))
        @test load_sim_data(b).u[1][1] == 2.0 && load_sim_data(a).u[1][1] == 1.0
        @test !haskey(load_sim_data(a).metadata, :postprocessed)
    end

    @testset "3. an import with other parameters drops what the statistics pass evaluated with the old ones" begin
        h3_fresh()
        a, b = h3_diag(1), h3_diag(2)
        cfg(p) = SimulationConfig(p; reference = :h3_double_reference, postprocess = :h3_add_one)
        run_all_simulations(cfg(a); calculate_stats = true)
        d = load_sim_data(a)
        @test d.u[1][1] == 2.0 && d.stats[:l1error][1] == 2.0 && haskey(d.metadata, :postprocessed)   # (|1 - 2| twice, before +1)
        source = get_file_name(a)
        h3_fresh()
        imported = mktemp() do _, io
            write(io, "2\n"); flush(io); seekstart(io)
            redirect_stdout(devnull) do
                redirect_stdin(() -> import_sim_data(source; prompt_keys = [:k]), io)
            end
        end
        @test length(imported) == 1
        d = load_sim_data(b)
        @test !haskey(d.stats, :l1error) && d.stats[:iterations][1] == 23.0 && haskey(d.metadata, :postprocessed)
        @test !PDEStudioCore.JLD2.jldopen(f -> haskey(f, "evaluated_with_reference") || haskey(f, "evaluated_stats"), get_file_name(b), "r")
        s = run_all_simulations(cfg(b); calculate_stats = true)
        d = load_sim_data(b)
        @test get(s.stats, :ran, 0) == 1 && d.stats[:l1error][1] == 4.0   # (|2 - 4| on two unit-spaced nodes)
        @test d.u[1][1] == 2.0 && d.stats[:iterations][1] == 23.0 && get(s.postprocessing, :ran, 0) == 0   # (not post-processed twice)
    end

    @testset "4./5. Float16 spacing and statistics don't overflow where the result doesn't" begin
        for T in (Float16, Float32, Float64)
            d = create_sim_data(T[-40000, 0, 40000], T[0.25, 0.25, 0.25], ParamDict())
            calculate_all_stats!(d; save = false)
            @test d.domain.spacing[1] == T(40000) && d.stats[:mass][1] == T(30000) && d.stats[:mass] isa SVector{1, T}
            d = create_sim_data(T[0, 1], T[300, 300], ParamDict())
            calculate_all_stats!(d; save = false)
            @test d.stats[:l2norm][1] ≈ T(sqrt(2) * 300) rtol = 1e-3
        end
        # resampled and reference grids
        t = Float16[0, 30000, 60000]
        e = create_sim_data(Float16[-40000, 0, 40000], fill(Float16(1), 3, 3), t, ParamDict())
        r = resample_eulerian(e, (5, 3))
        @test all(isfinite, r.domain.spacing) && r.domain.spacing[1] == Float16(20000) && e.domain.spacing[2] == Float16(30000)
        @test PDEStudioCore._grid_spacing((Float16[-40000, 0, 40000],), Float16)[1] == Float16(40000)
        lag = create_sim_data([[SVector(Float16(-40000)), SVector(Float16(40000))]], [[SVector(Float16(1)), SVector(Float16(1))]],
                              Float16[0], ParamDict())
        @test isfinite(convert_to_eulerian(lag, (3, 1)).domain.spacing[1])
    end

    @testset "6. a source replaced by another valid version during a prompt is reported" begin
        h3_fresh()
        p = h3_params("run")
        dest = h3_save(p, 7)
        original = read(dest)
        folder = mktempdir()
        src = joinpath(folder, "a-incoming.jld2")
        cp(dest, src)
        cp(h3_save(h3_params("other"), 11), joinpath(folder, "z-next.jld2"))
        newer = joinpath(mktempdir(), "newer.jld2")
        h3_fresh(); cp(h3_save(p, 91), newer)   # (a complete run of the same parameters, field 91)
        set_save_path!(dirname(dirname(dest)))
        H3_SWAP[] = (src, newer)
        imported = mktemp() do _, io
            write(io, "\nh3_swap_during_prompt()\n"); flush(io); seekstart(io)
            redirect_stdout(devnull) do
                redirect_stdin(io) do
                    @test_logs (:warn, r"content changed") match_mode = :any import_sim_data(folder; prompt_keys = [:k], overwrite = true)
                end
            end
        end
        @test length(imported) == 1 && read(dest) == original && h3_stored(dest) == ("run", 7.0)
    end

    @testset "7. a data folder that isn't a directory fails each import, not the batch" begin
        h3_fresh()
        external = joinpath(mktempdir(), "run.jld2")
        mv(h3_save(h3_params("first"), 7), external)
        dir = joinpath(get_save_path(), "data")
        rm(dir; recursive = true)
        write(dir, "store path occupied by a regular file")
        @test isempty(@test_logs (:warn, r"Not imported") match_mode = :any import_sim_data(external)) && isfile(external)
        h3_fresh()   # (later tests save to the save path)
    end
end

# Fixes of the review of #42 (reviews/2026-11-24-pull42-codex.md), one case per finding
h3_popping_reference(p) = (pop!(p, :offset); _ -> 0.0)   # (a reference factory that takes its parameter out)

@testset "Review fixes (#42)" begin
    # 1. and 4. (no second post-processing after an import, solver statistics kept): `Review fixes (2026-11-24)`, case 3
    @testset "2. integer and rational statistics stay exact" begin
        old = PDEStudioCore.get_stat_registry()
        try
            set_stat_registry!(Dict(:mass => :time))
            d = DomainInfo{1, Int}((:x,), (0,), (1,), (1,), nothing)
            vals = [2^53 + 1, -2^53]
            field = ESimData(ParamDict(), d, ([0, 1],), SVector.(vals))
            calculate_all_stats!(field, _ -> 0; save = false)
            @test field.stats[:mass][1] === 1
            r = DomainInfo{1, Rational{Int}}((:x,), (0 // 1,), (1 // 1,), (1 // 1,), nothing)
            rf = ESimData(ParamDict(), r, ([0 // 1, 1 // 1],), SVector.([1 // 3, 1 // 6]))
            calculate_all_stats!(rf, _ -> 0; save = false)
            @test rf.stats[:mass][1] === 1 // 2
        finally
            set_stat_registry!(old)
        end
    end

    @testset "3. rational grids keep exact spacings" begin
        T = Rational{Int}
        lo = 10^16 // 1
        bounds = DomainInfo{1, T}((:x,), (lo,), (lo + 1,), (1 // 1,), nothing)
        ref = generate_reference_simdata(_ -> 1 // 1, ParamDict(), bounds, (2,), :eulerian)
        @test ref.axes[1][2] - ref.axes[1][1] == 1 && only(ref.domain.spacing) === 1 // 1
        unit = DomainInfo{1, T}((:x,), (0 // 1,), (1 // 1,), (1 // 3,), nothing)
        @test only(generate_reference_simdata(_ -> SVector(1 // 1), ParamDict(), unit, (4,), :eulerian).domain.spacing) === 1 // 3
        @test PDEStudioCore._axis_spacing(0 // 1, 1 // 1, 4, T) === 1 // 3
    end

    @testset "outside: a reference factory gets a copy of the task" begin
        h3_fresh()
        p = create_param_dict(:sim_func_name => :h3_solver, :k => 10, :offset => 5)
        other = create_param_dict(:sim_func_name => :h3_solver, :k => 10)
        save_sim_data(create_sim_data([0.0, 1.0], [80.0, 80.0], other); verbose = false)
        s = run_all_simulations(SimulationConfig(p; reference = :h3_popping_reference, postprocess = :h3_add_one); calculate_stats = true)
        @test load_sim_data(p).u[1][1] == 11.0 && load_sim_data(other).u[1][1] == 80.0
        @test haskey(only(s.tasks), :offset) && get(s.postprocessing, :ran, 0) == 1
    end

    @testset "outside: a rewrite keeps attributes and empty groups, or fails" begin
        JLD2 = PDEStudioCore.JLD2
        h3_fresh()
        p = h3_params("entries")
        d = h3_data(p, 1)
        path = save_sim_data(d; verbose = false)
        JLD2.jldopen(path, "a+") do f
            ds = JLD2.create_dataset(f, "calibration")
            JLD2.add_attribute(ds, "units", "kelvin")
            JLD2.write_dataset(ds, 47)
            JLD2.Group(f, "pending_measurements")
            g = JLD2.Group(f, "outer")
            inner = JLD2.Group(g, "inner")
            nested = JLD2.create_dataset(inner, "x")
            JLD2.add_attribute(nested, "a", 1.5)
            JLD2.write_dataset(nested, [1, 2])
        end
        d.metadata[:note] = "completed"
        save_sim_data(d; overwrite = true, verbose = false)
        JLD2.jldopen(path, "r") do f
            @test f["calibration"] == 47 && JLD2.attributes(JLD2.get_dataset(f, "calibration"))["units"] == "kelvin"
            @test haskey(f, "pending_measurements") && isempty(keys(f["pending_measurements"]))
            @test f["outer/inner/x"] == [1, 2] && JLD2.attributes(JLD2.get_dataset(f["outer"]["inner"], "x"))["a"] == 1.5
        end
        @test load_sim_data(p).metadata[:note] == "completed"
    end
end
