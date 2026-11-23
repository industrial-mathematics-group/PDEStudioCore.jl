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
