# Fixes of the A2 review of the hash format 3 (reviews/2026-11-23-hash-format-3-codex.md), one case per finding
@testset "Review fixes (hash format 3)" begin
    h3_params(v) = create_param_dict(:k => v)
    h3_data(p, v) = create_sim_data([0.0, 1.0], fill(Float64(v), 2), p)
    h3_save(p, v; kw...) = save_sim_data(h3_data(p, v); verbose = false, kw...)
    h3_stored(path) = PDEStudioCore.JLD2.jldopen(f -> (f["params"][:k], f["raw"].u[1][1]), path, "r")
    h3_fresh() = (root = mktempdir(); set_save_path!(root); joinpath(root, "data"))

    @testset "1. a file replaced with its modification time kept is read again" begin
        h3_fresh()
        a = h3_save(h3_params("A"), 10)
        b = h3_save(h3_params("B"), 20)
        Sys.islinux() && run(`touch -r $a $b`)                     # (the replacement keeps the time)
        @test get_file_name(h3_params("A")) == a                   # (warms the cache)
        mv(b, a; force = true)
        @test h3_stored(a) == ("B", 20.0)
        a2 = h3_save(h3_params("A"), 30; overwrite = true)
        @test h3_stored(a) == ("B", 20.0)                          # B is not replaced by A
        @test a2 != a && h3_stored(a2) == ("A", 30.0)
    end

    @testset "2. true is not 1 when a stored file is checked" begin
        dir = h3_fresh()
        b = h3_save(h3_params(true), 20)
        a = joinpath(dir, "restored_" * calculate_hash(h3_params(1)) * ".jld2")
        mv(b, a)
        @test calculate_hash(h3_params(true)) != calculate_hash(h3_params(1))
        a2 = h3_save(h3_params(1), 30; overwrite = true)
        @test h3_stored(a) == (true, 20.0) && a2 != a
        @test isnothing(PDEStudioCore._find_file(h3_params(1 => 1))) || true   # (no exception for other values)
    end

    @testset "3. staging: long names, a failing move changes nothing, an interrupted run is undone" begin
        dir = h3_fresh()
        short = joinpath(dir, "a_" * "0"^64 * ".jld2")
        long = joinpath(dir, "z"^182 * "_" * "1"^64 * ".jld2")   # 252 bytes: legal, no room for a suffix
        mv(h3_save(h3_params("short"), 1), short)
        mv(h3_save(h3_params("long"), 2), long)
        renamed = rehash_sim_data(dir)
        @test length(renamed) == 2 && !any(f -> endswith(f, ".tmp") || startswith(f, ".rehash"), readdir(dir))
        @test length(find_sim_data(h3_params("short"); verbose = false)) == 1
        @test length(find_sim_data(h3_params("long"); verbose = false)) == 1
        # a file set aside by an interrupted run comes back with the next one
        stage = joinpath(dir, PDEStudioCore._STAGE_PREFIX * "0")
        mkpath(stage)
        f = first(find_sim_data(h3_params("short"); verbose = false))
        mv(f, joinpath(stage, basename(f)))
        @test isempty(find_sim_data(h3_params("short"); verbose = false))
        rehash_sim_data(dir)
        @test isfile(f) && !isdir(stage) && length(find_sim_data(h3_params("short"); verbose = false)) == 1
    end

    if Sys.isunix()
        @testset "4. a link to a file of the batch does not break the batch" begin
            dir = h3_fresh()
            both = create_param_dict(:k => "target", :obsolete => 1)
            target = joinpath(dir, "z_" * calculate_hash(both) * ".jld2")
            mv(h3_save(both, 20), target)
            link = joinpath(dir, "a_" * calculate_hash(both) * ".jld2")
            symlink(basename(target), link)
            renamed = @test_logs (:warn, r"links to files of this batch") match_mode = :any rehash_sim_data(dir; remove_keys = [:obsolete])
            @test length(renamed) == 1
            @test length(find_sim_data(h3_params("target"); verbose = false)) == 1
            @test !any(f -> islink(joinpath(dir, f)) || endswith(f, ".tmp"), readdir(dir))
        end
    end

    @testset "5. tidy removes duplicates by what the files hold" begin
        dir = h3_fresh()
        original = h3_save(h3_params("A"), 10)
        wrong = joinpath(dir, "z_" * calculate_hash(h3_params("A")) * ".jld2")
        mv(h3_save(h3_params("B"), 20), wrong)
        Sys.islinux() && run(`touch -r $original $wrong`)
        @test h3_stored(get_file_name(h3_params("A"))) == ("A", 10.0)
        result = tidy_sim_data()
        @test isempty(result.duplicates)                            # two runs, no duplicate: nothing removed
        @test Set(last.(h3_stored.(find_sim_data(; verbose = false)))) == Set([10.0, 20.0])
        dup = h3_save(h3_params("A"), 10)                           # a real duplicate (same parameters) under another name
        sleep(0.05)
        dup2 = h3_save(h3_params("A"), 11; overwrite = false)       # (not saved: a file exists)
        cp(original, joinpath(dir, "copy_" * calculate_hash(h3_params("A")) * ".jld2"))
        result = tidy_sim_data()
        @test length(result.duplicates) == 1 && length(find_sim_data(h3_params("A"); verbose = false)) == 1
    end

    @testset "6. integer and Float16 particle domains" begin
        d = DomainInfo{1, Int}((:x,), (0,), (1,), (1,), nothing)
        particles = LSimData(ParamDict(), d, [0], [[SVector(0), SVector(1)]], [[SVector(2), SVector(2)]])
        @test first.(convert_to_eulerian(particles, (2,)).u) == [2, 2]
        x16 = [SVector(Float16(-40000)), SVector(Float16(40000))]                 # static particles
        p16 = create_sim_data(x16, [SVector(Float16(0.25)), SVector(Float16(0.25))], ParamDict())
        @test p16.domain.spacing[1] == Float16(40000)
    end

    @testset "7. the parameter cache does not keep deleted files" begin
        cache = PDEStudioCore._STORED_PARAMS
        seen = String[]
        for n in 1:4
            h3_fresh()
            q = h3_params(string(n) * repeat("x", 4096))
            push!(seen, h3_save(q, n))
            get_file_name(q)
            delete_sim_data(q)
        end
        h3_fresh()
        PDEStudioCore._data_index(fresh = true)
        @test count(k -> haskey(cache, k), seen) == 0
    end
end
