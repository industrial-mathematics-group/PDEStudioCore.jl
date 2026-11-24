# The store and its contract (docs/src/data.md, "3. Storage Layout"): one file per run under the hash of its
# parameters; a file is only taken for, and replaced by, the run its name stands for; data is only written to its own
# name, atomically; the store keeps no symbolic links; an import only reads its source, which lies outside the data
# folder; data is floating point. The cases of the reviews of 2026-11-23/24 (reviews/) that are within the contract are
# kept here, grouped by rule.
st_params(v) = create_param_dict(:k => v)
st_data(p, v) = create_sim_data([0.0, 1.0], fill(Float64(v), 2), p)
st_save(p, v; kw...) = save_sim_data(st_data(p, v); verbose = false, kw...)
st_stored(path) = PDEStudioCore.JLD2.jldopen(f -> (f["params"][:k], f["raw"].u[1][1]), path, "r")
st_fresh() = (root = mktempdir(); set_save_path!(root); joinpath(root, "data"))
st_name(p) = PDEStudioCore._hash_path(calculate_hash(p))
st_snapshot(dir) = Dict(relpath(joinpath(r, f), dir) => (islink(joinpath(r, f)) ? readlink(joinpath(r, f)) : read(joinpath(r, f)))
                        for (r, _, fs) in walkdir(dir) for f in fs)
st_case(k) = create_param_dict(:sim_func_name => :st_solver, :k => k)
st_solver(p) = create_sim_data([0.0, 1.0], fill(Float64(p[:k]), 2), p)
st_diag_solver(p) = (d = st_solver(p); add_stat!(d, :iterations, 23.0, Symbol[]); d)   # (a solver diagnostic)
st_double_reference(p) = _ -> 2 * p[:k]
const ST_MARKS = Ref(0)
st_mark(data) = (ST_MARKS[] += 1; add_stat!(data, :marked, 1.0, Symbol[]); true)   # (adds a statistic, keeps u)
st_moving_post(data) = (data.params[:k] = 2; true)
st_popping_reference(p) = (pop!(p, :offset); _ -> 0.0)   # (a reference factory that takes its parameter out)

struct StCalibration
    value::Int
end
const ST_WRITE = Ref(true)   # (a type whose stored form reads, but can't be written in this session)
PDEStudioCore.JLD2.writeas(::Type{StCalibration}) = Int
PDEStudioCore.JLD2.wconvert(::Type{Int}, x::StCalibration) = ST_WRITE[] ? x.value : error("calibration writer unavailable")
PDEStudioCore.JLD2.rconvert(::Type{StCalibration}, x::Int) = StCalibration(x)

@testset "Store: a file is only taken for, and replaced by, its run" begin
    # a file replaced with its modification time kept is read again
    st_fresh()
    a = st_save(st_params("A"), 10)
    b = st_save(st_params("B"), 20)
    Sys.islinux() && run(`touch -r $a $b`)
    @test get_file_name(st_params("A")) == a   # (warms the cache)
    mv(b, a; force = true)
    @test st_stored(a) == ("B", 20.0) && !does_sim_data_exist(st_params("A"))
    @test_throws r"other parameters" st_save(st_params("A"), 30; overwrite = true)
    @test st_stored(a) == ("B", 20.0)
    # `true` is not `1`
    st_fresh()
    mv(st_save(st_params(true), 20), st_name(st_params(1)))
    @test calculate_hash(st_params(true)) != calculate_hash(st_params(1)) && isnothing(PDEStudioCore._find_file(st_params(1)))
    @test_throws r"other parameters" st_save(st_params(1), 30; overwrite = true)
    @test st_stored(st_name(st_params(1))) == (true, 20.0)
end

if Sys.isunix()
    @testset "Store: no symbolic links" begin
        dir = st_fresh()
        p = st_params("run")
        dest = st_save(p, 7)
        external = joinpath(mktempdir(), "external.jld2")
        mv(dest, external)
        symlink(external, dest)
        # a link at a run's name is never taken for the run, written through or replaced
        @test !does_sim_data_exist(p) && isempty(find_sim_data(; verbose = false)) && size(sim_data_table(), 1) == 0
        @test_throws r"symbolic link" st_save(p, 9; overwrite = true)
        @test islink(dest) && st_stored(external) == ("run", 7.0)
        @test tidy_sim_data().foreign == [dest]
        src = joinpath(mktempdir(), "run.jld2")
        cp(external, src)
        @test isempty(@test_logs (:warn, r"symbolic link") match_mode = :any import_sim_data(src)) && islink(dest)
        @test_throws r"symbolic link" PDEStudioCore._set_key!(dest, "evaluated_with_reference", true)
        # also one whose target is missing
        rm(dest)
        symlink(joinpath(dir, "separate-mount.jld2"), dest)
        @test_throws r"symbolic link" st_save(p, 7)
        @test islink(dest) && !ispath(joinpath(dir, "separate-mount.jld2"))
    end
end

@testset "Store: tidy never deletes data" begin
    dir = st_fresh()
    original = st_save(st_params("A"), 10)
    wrong = joinpath(dir, "z_" * calculate_hash(st_params("A")) * ".jld2")   # (another run under A's hash)
    mv(st_save(st_params("B"), 20), wrong)
    partial = joinpath(dir, "1"^64 * ".jld2")                                # (a copy without its dataset)
    cp(original, partial)
    PDEStudioCore.JLD2.jldopen(f -> delete!(f, "raw"), partial, "a+")
    Sys.islinux() && run(`touch -d "2020-01-01" $original`)                # (the complete file is the oldest)
    tmp = PDEStudioCore._tmp_path(original)
    write(tmp, "an unfinished write")
    result = tidy_sim_data(min_tmp_age = 0)
    @test sort(result.foreign) == sort([wrong, partial]) && result.temp_files == [tmp] && !ispath(tmp)
    @test isfile(original) && isfile(wrong) && isfile(partial) && st_stored(get_file_name(st_params("A"))) == ("A", 10.0)
    @test !does_sim_data_exist(st_params("B"))   # (B is under another name: move it out and import it)
end

@testset "Store: filters tell values apart like the hash" begin
    st_fresh()
    a, b, c = st_save(st_params(1), 7), st_save(st_params(true), 9), st_save(st_params(1.0), 8)
    @test find_sim_data(Dict(:k => 1); verbose = false) == [a] && delete_sim_data(Dict(:k => 1); dry_run = true) == [a]
    @test find_sim_data(Dict(:k => true); verbose = false) == [b] && find_sim_data(Dict("k" => 1.0); verbose = false) == [c]
    @test size(sim_data_table(Dict(:k => 1)), 1) == 1
    src = mktempdir()
    foreach(f -> cp(f, joinpath(src, basename(f))), (a, b, c))
    st_fresh()
    @test last.(import_sim_data(src; filter_pairs = Dict(:k => 1))) == [st_name(st_params(1))]
    @test delete_sim_data(Dict(:k => 1)) == [st_name(st_params(1))] && isempty(find_sim_data(; verbose = false))
end

@testset "Import: the source is only read, and lies outside the data folder" begin
    dir = st_fresh()
    stored = st_save(st_params("stored"), 1)
    @test_throws r"overlap" import_sim_data(dir)
    @test_throws r"overlap" import_sim_data(stored)
    @test_throws r"overlap" import_sim_data(get_save_path())
    mkpath(joinpath(dir, "sub"))
    @test_throws r"overlap" import_sim_data(joinpath(dir, "sub"))
    @test_throws MethodError import_sim_data(mktempdir(); prompt_keys = [:k])   # (removed: rerun the solver instead)
    @test_throws MethodError import_sim_data(mktempdir(); overwrite = true)
    # long names; a link next to its target (one run); links read where they are; a filter changes nothing
    src = mktempdir()
    mv(st_save(st_params("short"), 1), joinpath(src, "a_" * "0"^64 * ".jld2"))
    mv(st_save(st_params("long"), 2), joinpath(src, "z"^182 * "_" * "1"^64 * ".jld2"))   # (252 bytes)
    both = create_param_dict(:k => "target", :obsolete => 1)
    mv(st_save(both, 20), joinpath(src, "m_target.jld2"))
    Sys.isunix() && symlink("m_target.jld2", joinpath(src, "m_link.jld2"))
    outer = mktempdir()
    mv(st_save(create_param_dict(:k => "shared", :obsolete => 1), 5), joinpath(outer, "shared.jld2"))
    Sys.isunix() && symlink(joinpath("..", basename(outer), "shared.jld2"), joinpath(src, "relative.jld2"))
    before, before_outer = st_snapshot(src), st_snapshot(outer)
    @test isempty(import_sim_data(src; filter_pairs = Dict(:k => "unmatched"))) && st_snapshot(src) == before
    imported = import_sim_data(src; remove_keys = [:obsolete])
    @test length(imported) == (Sys.isunix() ? 4 : 3) && st_snapshot(src) == before && st_snapshot(outer) == before_outer
    @test st_stored(get_file_name(st_params("short"))) == ("short", 1.0) && st_stored(get_file_name(st_params("long"))) == ("long", 2.0)
    @test st_stored(get_file_name(st_params("target"))) == ("target", 20.0)
    Sys.isunix() && @test st_stored(get_file_name(st_params("shared"))) == ("shared", 5.0)
    @test !any(f -> endswith(f, ".tmp"), readdir(dirname(get_file_name(st_params("short")))))
    @test isempty(import_sim_data(src; remove_keys = [:obsolete]))   # (stored already)
    # an interrupted import leaves at most a temporary file: the retry imports, tidy removes it
    st_fresh()
    src = mktempdir()
    old = joinpath(src, "2026-01-01_00-00-00_000_" * "2"^64 * ".jld2")
    mv(st_save(st_params("only"), 4), old)
    tmp = PDEStudioCore._tmp_path(st_name(st_params("only")))
    write(tmp, "half a file")
    @test length(import_sim_data(src)) == 1 && st_stored(get_file_name(st_params("only"))) == ("only", 4.0)
    @test tidy_sim_data(min_tmp_age = 0).temp_files == [tmp] && isfile(old)
end

@testset "Import: what is installed is checked" begin
    corrupt!(path) = PDEStudioCore.JLD2.jldopen(f -> (delete!(f, "raw"); f["raw"] = "not a simulation dataset"), path, "a+")
    st_fresh()
    good = st_save(st_params("run"), 7)
    src = mktempdir()
    bad = joinpath(src, "bad.jld2")
    cp(good, bad)
    corrupt!(bad)
    other = joinpath(src, "other.jld2")   # (a dataset of other parameters than the file says)
    cp(good, other)
    PDEStudioCore.JLD2.jldopen(f -> (delete!(f, "params"); f["params"] = st_params("else")), other, "a+")
    st_fresh()
    imported = @test_logs (:warn, r"no dataset") (:warn, r"other parameters than the file") match_mode = :any import_sim_data(src)
    @test isempty(imported) && isempty(find_sim_data(; verbose = false))
    # a filter excludes a run before its dataset is read
    @test isempty(@test_logs min_level = Base.CoreLogging.Warn import_sim_data(bad; filter_pairs = Dict(:k => "unmatched")))
    # nothing at a destination is replaced: neither a stored file of the parameters that isn't a usable run, nor a
    # file of other parameters
    p = st_params("retry")
    dest = st_save(p, 7)
    complete = joinpath(mktempdir(), "complete.jld2")
    cp(dest, complete)
    PDEStudioCore.JLD2.jldopen(f -> delete!(f, "raw"), dest, "a+")
    @test !does_sim_data_exist(p)
    @test isempty(@test_logs (:warn, r"isn't a usable run") match_mode = :any import_sim_data(complete))
    @test !does_sim_data_exist(p) && !PDEStudioCore.JLD2.jldopen(f -> haskey(f, "raw"), dest, "r")
    rm(dest)
    @test length(import_sim_data(complete)) == 1 && does_sim_data_exist(p) && st_stored(dest) == ("retry", 7.0)
    run_c = joinpath(mktempdir(), "run_c.jld2")
    st_fresh(); cp(st_save(st_params("C"), 3), run_c)
    mv(st_save(st_params("B"), 20), st_name(st_params("C")); force = true)   # (B's data under C's name)
    @test isempty(@test_logs (:warn, r"other parameters") match_mode = :any import_sim_data(run_c))
    @test st_stored(st_name(st_params("C"))) == ("B", 20.0)
    # a data folder that isn't a directory fails each import, not the batch
    st_fresh()
    external = joinpath(mktempdir(), "run.jld2")
    mv(st_save(st_params("first"), 7), external)
    data = joinpath(get_save_path(), "data")
    rm(data; recursive = true)
    write(data, "store path occupied by a regular file")
    @test isempty(@test_logs (:warn, r"Not imported") match_mode = :any import_sim_data(external)) && isfile(external)
    st_fresh()   # (later tests save to the save path)
end

@testset "Import: removed keys keep the data and its records" begin
    st_fresh()
    a = create_param_dict(:sim_func_name => :st_diag_solver, :k => 1, :obsolete => "x")
    b = create_param_dict(:sim_func_name => :st_diag_solver, :k => 1)
    cfg(p) = SimulationConfig(p; reference = :st_double_reference, postprocess = :st_mark)
    ST_MARKS[] = 0
    run_all_simulations(cfg(a); calculate_stats = true)
    d = load_sim_data(a)
    @test d.stats[:l1error][1] == 2.0 && d.stats[:marked][1] == 1.0 && ST_MARKS[] == 1   # (|1 - 2| twice)
    moved = mktempdir()
    mv(get_file_name(a), joinpath(moved, "a.jld2"))
    @test length(import_sim_data(moved; remove_keys = [:obsolete])) == 1
    d = load_sim_data(b)
    @test d.stats[:l1error][1] == 2.0 && d.stats[:iterations][1] == 23.0 && d.stats[:marked][1] == 1.0 && haskey(d.metadata, :postprocessed)
    @test PDEStudioCore.JLD2.jldopen(f -> haskey(f, "evaluated_stats") && haskey(f, "evaluated_with_reference"), get_file_name(b), "r")
    s = run_all_simulations(cfg(b); calculate_stats = true)   # (nothing to do: not solved, evaluated or post-processed again)
    @test isempty(s.ran) && get(s.stats, :ran, 0) == 0 && get(s.postprocessing, :ran, 0) == 0 && ST_MARKS[] == 1
end

@testset "Rewrites keep every entry, or fail" begin
    JLD2 = PDEStudioCore.JLD2
    # an entry that can't be written again fails the rewrite; the file stays as it was
    st_fresh()
    p = st_params("calibrated")
    data = st_data(p, 1)
    path = save_sim_data(data; verbose = false)
    JLD2.jldopen(f -> (f["calibration"] = StCalibration(47)), path, "a+")
    before = read(path)
    ST_WRITE[] = false
    data.metadata[:units] = "K"
    try
        @test_throws r"entry 'calibration'.*can't be carried over"s save_sim_data(data; overwrite = true, verbose = false)
    finally
        ST_WRITE[] = true
    end
    @test read(path) == before && !any(f -> endswith(f, ".tmp"), readdir(dirname(path)))
    @test JLD2.jldopen(f -> f["calibration"].value, path, "r") == 47
    # attributes of datasets and groups (also empty ones) are kept
    st_fresh()
    p = st_params("entries")
    d = st_data(p, 1)
    path = save_sim_data(d; verbose = false)
    JLD2.jldopen(path, "a+") do f
        ds = JLD2.create_dataset(f, "calibration")
        JLD2.add_attribute(ds, "units", "kelvin")
        JLD2.write_dataset(ds, 47)
        JLD2.Group(f, "pending_measurements")
        nested = JLD2.create_dataset(JLD2.Group(JLD2.Group(f, "outer"), "inner"), "x")
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

@testset "Callbacks can't redirect a save to another run" begin
    # a post-processor that changes the parameters fails
    st_fresh()
    a, b = st_case(1), st_case(2)
    save_sim_data(st_solver(b); verbose = false)
    s = run_all_simulations(SimulationConfig(a; postprocess = :st_moving_post))
    @test s.postprocessing[:failed] == 1 && occursin("changed the parameters", last(only(s.postprocessing_failed)))
    @test load_sim_data(b).u[1][1] == 2.0 && load_sim_data(a).u[1][1] == 1.0 && !haskey(load_sim_data(a).metadata, :postprocessed)
    # a reference factory gets a copy of the task
    st_fresh()
    p = create_param_dict(:sim_func_name => :st_solver, :k => 10, :offset => 5)
    other = create_param_dict(:sim_func_name => :st_solver, :k => 10)
    save_sim_data(create_sim_data([0.0, 1.0], [80.0, 80.0], other); verbose = false)
    s = run_all_simulations(SimulationConfig(p; reference = :st_popping_reference, postprocess = :st_mark); calculate_stats = true)
    @test haskey(load_sim_data(p).stats, :marked) && !haskey(load_sim_data(other).stats, :marked)
    @test load_sim_data(other).u[1][1] == 80.0 && haskey(only(s.tasks), :offset) && get(s.postprocessing, :ran, 0) == 1
end

@testset "Data is floating point; Float16 doesn't overflow where the result doesn't" begin
    @test_throws TypeError DomainInfo{1, Int}((:x,), (0,), (1,), (1,), nothing)
    @test_throws TypeError DomainInfo{1, Rational{Int}}((:x,), (0 // 1,), (1 // 1,), (1 // 1,), nothing)
    @test DomainInfo((:x,), (0,), (1,), (1,), nothing) isa DomainInfo{1, Float64}
    @test create_sim_data([0, 1], [2, 3], ParamDict()) isa ESimData{1, 1, 1, Float64}
    @test create_sim_data([0 // 1, 1 // 1], [1 // 3, 1 // 6], ParamDict()).u[1][1] == 1 / 3
    @test create_sim_data([SVector(0), SVector(1)], [SVector(2), SVector(2)], ParamDict()) isa LSimData{1, 1, 1, Float64}
    for T in (Float16, Float32, Float64)
        d = create_sim_data(T[-40000, 0, 40000], T[0.25, 0.25, 0.25], ParamDict())
        calculate_all_stats!(d; save = false)
        @test d.domain.spacing[1] == T(40000) && d.stats[:mass][1] == T(30000) && d.stats[:mass] isa SVector{1, T}
        d = create_sim_data(T[0, 1], T[300, 300], ParamDict())
        calculate_all_stats!(d; save = false)
        @test d.stats[:l2norm][1] ≈ T(sqrt(2) * 300) rtol = 1e-3
    end
    e = create_sim_data(Float16[-40000, 0, 40000], fill(Float16(1), 3, 3), Float16[0, 30000, 60000], ParamDict())
    r = resample_eulerian(e, (5, 3))
    @test r.domain.spacing[1] == Float16(20000) && e.domain.spacing[2] == Float16(30000)
    @test PDEStudioCore._grid_spacing((Float16[-40000, 0, 40000],), Float16)[1] == Float16(40000)
    x16 = [SVector(Float16(-40000)), SVector(Float16(40000))]   # (static particles)
    p16 = create_sim_data(x16, [SVector(Float16(0.25)), SVector(Float16(0.25))], ParamDict())
    @test p16.domain.spacing[1] == Float16(40000)
    lag = create_sim_data([x16], [[SVector(Float16(1)), SVector(Float16(1))]], Float16[0], ParamDict())
    @test isfinite(convert_to_eulerian(lag, (3, 1)).domain.spacing[1])
end

@testset "Store: the parameter cache is bounded" begin
    cache = PDEStudioCore._STORED_IDENTITY
    for n in 1:4
        st_fresh()
        q = st_params(string(n) * repeat("x", 4096))
        st_save(q, n)
        get_file_name(q)
        delete_sim_data(q)
    end
    @test length(cache) <= PDEStudioCore._STORED_MAX
    foreach(i -> (cache["/nonexistent/$i"] = ((UInt(0), 0, 0.0), nothing)), 1:PDEStudioCore._STORED_MAX)
    st_fresh()
    st_save(st_params("after"), 1)
    get_file_name(st_params("after"))
    @test length(cache) < 10
end

# Fixes of the independent review of 0.9.0 (2026-11-24; report in the PR), one case per finding
module StTags
using PDEStudioCore
@param_struct struct Limiter{K} end
@param_struct struct Wall
    id::Int
end
end
st_flat(p) = create_sim_data(collect(range(0, 1, length = 5)), fill(Float64(p[:k]), 5), p)
st_double(data) = (data.u = map(v -> 2 .* v, data.u); true)   # (changes the solution)
st_large(p) = create_sim_data(collect(range(0.0, 1.0, length = p[:n])), collect(1.0:p[:n]), p)
st_poke(data) = (data.u[1] = SVector(101.0); true)              # (changes one entry of 50 000)
st_own_error(data) = (add_stat!(data, :l1error, 7.0, :time); true)   # (a post-processor's own error statistic)

@testset "Review fixes (0.9.0)" begin
    @testset "1. the stored form doesn't depend on what the session loaded with `using`" begin
        SV = PDEStudioCore.StaticArrays.SVector
        p = Dict(:sources_at => [SV(0.25, 0.5), SV(0.75, 0.5)])
        @test get_clean_params(p)[:sources_at] == [SV(0.25, 0.5), SV(0.75, 0.5)]   # (read back as values, not text)
        code = "using PDEStudioCore; SV = PDEStudioCore.StaticArrays.SVector; " *
               "print(calculate_hash(Dict(:sources_at => [SV(0.25, 0.5), SV(0.75, 0.5)])))"
        @test read(`$(Base.julia_cmd()) --project=$(Base.active_project()) -e $code`, String) == calculate_hash(p)
        @test val2str([StTags.Wall(1)]) == "Wall[Wall(id=1)]"   # (no `Main.StTags.` prefix)
        @test PDEStudioCore._type_text(Base.OneTo{Int}) == "OneTo{Int64}"
    end

    @testset "2. values stored alike are refused instead of merged; functions are refused" begin
        @test_throws r"is a function" get_clean_params(Dict(:ic => sin))
        @test_throws r":ics\[2\] is a function" calculate_hash(Dict(:ics => ["a", cos]))
        @test val2str(StTags.Limiter{:minmod}()) == "Limiter{:minmod}" && val2str(StTags.Limiter{:superbee}()) == "Limiter{:superbee}"
        @test calculate_hash(Dict(:l => StTags.Limiter{:minmod}())) != calculate_hash(Dict(:l => StTags.Limiter{:superbee}()))
        cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_flat, :k => 1, :x => 0.1);
                               varied = create_varied_dict(:x => Any[0.1f0, 0.1]))   # (Float32 is stored as Float64)
        @test_throws r"stored alike" generate_tasks(cfg)
    end

    @testset "3. a changed reference file is handled by on_changed_sources" begin
        st_fresh()
        src = joinpath(mktempdir(), "model.jl")
        write(src, "st_src_solver(p) = create_sim_data([0.0, 1.0], [1.0, 1.0], p)\nst_src_reference(p) = _ -> 2.0\n")
        cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_src_solver); reference = :st_src_reference, sources = [src])
        run(; kw...) = run_all_simulations(cfg; calculate_stats = true, kw...)
        @test run().stats == Dict(:ran => 1) && run().stats == Dict(:cached => 1)
        open(io -> println(io, "# a comment"), src, "a")
        s = @test_logs (:warn, r"another version of the reference") match_mode = :any run()
        @test s.stats == Dict(:outdated => 1)
        @test run(on_changed_sources = :ignore).stats == Dict(:cached => 1)
        @test run(on_changed_sources = :recompute).stats == Dict(:ran => 1) && run().stats == Dict(:cached => 1)
    end

    @testset "4. a save that keeps the stored data says so" begin
        st_fresh()
        p = st_params("kept")
        st_save(p, 1)
        @test_logs (:info, r"Not saved: data of these parameters is stored already") save_sim_data(st_data(p, 2))
        @test st_stored(get_file_name(p)) == ("kept", 1.0)
        PDEStudioCore.JLD2.jldopen(f -> delete!(f, "raw"), get_file_name(p), "a+")   # (and isn't replaced without `overwrite`)
        save_sim_data(st_data(p, 3); verbose = false)
        @test !does_sim_data_exist(p)
        save_sim_data(st_data(p, 3); overwrite = true, verbose = false)
        @test st_stored(get_file_name(p)) == ("kept", 3.0)
    end

    @testset "5. a statistic without a method fails instead of counting as evaluated" begin
        st_fresh()
        old = PDEStudioCore.get_stat_registry()
        try
            register_stat!(:st_umax, :time)
            cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_solver, :k => 3))
            s = run_all_simulations(cfg; calculate_stats = true)
            @test get(s.stats, :failed, 0) == 1 && occursin("has no `calc_stat", last(only(s.stats_failed)))
            @eval PDEStudioCore.calc_stat(::Val{:st_umax}, fixed, u, ana, domain) = maximum(u)
            s = run_all_simulations(cfg; calculate_stats = true)
            @test get(s.stats, :ran, 0) == 1 && haskey(load_sim_data(s.tasks[1]).stats, :st_umax)
        finally
            set_stat_registry!(old)
        end
    end

    @testset "6. methods named like references are reported" begin
        empty!(PDEStudioCore._WARNED_REFERENCE_NAMES)
        cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_solver, :k => 1),
                               Dict(:baseline => Dict(:k => 1), :weno => Dict(:k => 5)))
        @test_logs (:info, r"Method :baseline isn't run") match_mode = :any generate_tasks(cfg)
        @test length(generate_tasks(cfg)) == 1
    end

    @testset "7. relative_mass is relative" begin
        T = Float64
        domain = DomainInfo((:x,), (0.0,), (1.0,), (0.01,), nothing)
        u = [SVector(1e-10 * (1 + sin(2π * x))) for x in 0:0.01:0.99]
        @test calc_stat(Val(:relative_mass), (), u, u, domain)[1] ≈ 1.0   # (a small field keeps it)
        w = [SVector(sin(2π * x)) for x in 0:0.01:0.99]                  # (a reference whose mass cancels)
        @test isnan(calc_stat(Val(:relative_mass), (), w, w, domain)[1])
    end

    @testset "8. a post-processor that changes the solution fails (review of #46: also one entry of a large field)" begin
        st_fresh()
        cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_flat, :k => 1); postprocess = :st_double)
        s = run_all_simulations(cfg; calculate_stats = true)
        @test get(s.postprocessing, :failed, 0) == 1 && occursin("changed the solution", last(only(s.postprocessing_failed)))
        d = load_sim_data(generate_tasks(cfg)[1])
        @test d.u[1][1] == 1.0 && d.stats[:mass][1] ≈ 1.25 && !haskey(d.metadata, :postprocessed)   # (stored as it was)
        st_fresh()
        cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_large, :n => 50_000); postprocess = :st_poke)
        s = run_all_simulations(cfg; calculate_stats = true)
        @test get(s.postprocessing, :failed, 0) == 1 && load_sim_data(generate_tasks(cfg)[1]).u[1][1] == 1.0
        # a statistic the post-processor computes itself is kept, also one the statistics pass dropped (all NaN)
        st_fresh()
        cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_flat, :k => 2); postprocess = :st_own_error)
        run_all_simulations(cfg; calculate_stats = true)   # (no reference: :l1error is all NaN, dropped)
        @test load_sim_data(generate_tasks(cfg)[1]).stats[:l1error][1] == 7.0
        s = run_all_simulations(cfg; calculate_stats = true)
        @test load_sim_data(generate_tasks(cfg)[1]).stats[:l1error][1] == 7.0 && get(s.postprocessing, :skipped, 0) == 1
    end

    @testset "review of #46: quoted symbols in type parameters are data" begin
        l, r = Val{Symbol("left.mode")}(), Val{Symbol("right.mode")}()
        @test val2str(l) != val2str(r) && calculate_hash(Dict(:mode => l)) != calculate_hash(Dict(:mode => r))
        @test PDEStudioCore._type_text(Val{(Symbol("a.b"), :c)}) == "Val{(Symbol(\"a.b\"), :c)}"
    end

    @testset "the statistics of a file belong to one reference (reviews of #46 and #48)" begin
        st_fresh()
        src = joinpath(mktempdir(), "model.jl")
        model(c) = "st_src2_solver(p) = create_sim_data([0.0, 1.0], [1.0, 1.0], p)\nst_src2_reference(p) = _ -> $c\n"
        write(src, model(2.0))   # (reference A)
        cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_src2_solver); reference = :st_src2_reference, sources = [src])
        stats() = load_sim_data(generate_tasks(cfg)[1]).stats
        old = PDEStudioCore.get_stat_registry()
        try
            set_stat_registry!(Dict(:l1error => :time))
            run_all_simulations(cfg; calculate_stats = true)
            @test stats()[:l1error][1] == 2.0
            write(src, model(4.0))   # (reference B, same name: the code changed)
            @test run_all_simulations(cfg; calculate_stats = true).stats == Dict(:outdated => 1) && stats()[:l1error][1] == 2.0
            register_stat!(:l2error, :time)   # (a statistic is missing: all of them are evaluated with B, not a mix)
            s = @test_logs (:warn, r"evaluated\s+again with the current reference"s) match_mode = :any run_all_simulations(cfg; calculate_stats = true)
            @test s.stats == Dict(:refreshed => 1) && stats()[:l1error][1] == 6.0 && stats()[:l2error][1] ≈ sqrt(18)
            @test run_all_simulations(cfg; calculate_stats = true).stats == Dict(:cached => 1)
            write(src, model(2.0))   # (back to A: kept as outdated with :warn, evaluated again with :recompute)
            @test run_all_simulations(cfg; calculate_stats = true).stats == Dict(:outdated => 1)
            @test run_all_simulations(cfg; calculate_stats = true, on_changed_sources = :recompute).stats == Dict(:ran => 1)
            @test stats()[:l1error][1] == 2.0 && stats()[:l2error][1] ≈ sqrt(2)
        finally
            set_stat_registry!(old)
        end
    end

    @testset "review of #48: Unicode module names; Float32 scatter of large values" begin
        @eval module ΔStTags; export UnicodeTag; struct UnicodeTag{K} end; end
        p = Dict(:t => Val{ΔStTags.UnicodeTag{1}}())
        before = (val2str(p[:t]), calculate_hash(p))
        @eval using .ΔStTags: UnicodeTag
        @test before == (val2str(p[:t]), calculate_hash(p)) && before[1] == "Val{UnicodeTag{1}}()"
        lag = create_sim_data([[SVector(0.0f0), SVector(1.0f0)]], [[SVector(1.0f30), SVector(1.0f30)]], Float32[0], ParamDict())
        e = convert_to_eulerian(lag, (2, 1))
        @test all(v -> v[1] == 1.0f30, e.u) && eltype(eltype(e.u)) === Float32
    end

    @testset "contract: prefix loads skip links; complex data is refused" begin
        if Sys.isunix()
            dir = st_fresh()
            p = st_params("linked")
            path = st_save(p, 1)
            external = joinpath(mktempdir(), "external.jld2")
            mv(path, external); symlink(external, path)
            @test_throws SimFileNotFoundError load_sim_data(basename(path)[1:12])
        end
        @test_throws r"values of type ComplexF64" create_sim_data([0.0, 1.0], [1.0 + 2im, 2.0 + 0im], ParamDict())
        @test_throws r"values of type ComplexF64" create_sim_data([SVector(0.0)], [SVector(1.0 + 1im)], ParamDict())
        st_fresh()
    end
end

# The identity of parameter values (docs/src/data.md, "What identifies a parameter value"), pinned: the stored text and
# the hash of representative values, the same in this session (`using StaticArrays`) and in a fresh one without it.
# A failure here means normalisation changed: that is a new hash format, never a silent fix (CLAUDE.md).
const ST_CORPUS_PRELUDE = """
module StCorpus
using PDEStudioCore
abstract type AbstractBC end
@param_struct struct Wall <: AbstractBC; id::Int; end
@param_struct struct Limiter{K} end
struct Matrix end
struct Domain{GEO, FI, FT}   # (like a geometric domain: a label, data, functions and a derived field)
    label::GEO
    mins::Float64
    is_interior::FI
    get_tag::FT
    bc_map::Dict{Int, AbstractBC}
    volume::Float64
end
PDEStudioCore.param_identity(d::Domain) = (; label = d.label, mins = d.mins, bc_map = d.bc_map)
end
"""
const ST_CORPUS = [
    "50" => ("50", "b9f27849763fc3ee7361a06036ef329530f6b56e214c92ae61ef690d623f17fa"),
    "0.5" => ("0.5", "00ac8ba79233969e7ec276996b097ba8d96f2bdd1229580f6dfb3395a9c9ac67"),
    "0.5f0" => ("0.5", "00ac8ba79233969e7ec276996b097ba8d96f2bdd1229580f6dfb3395a9c9ac67"),
    "true" => ("true", "aa28ecfec4d33e8df0a1203198a50a45ccd4bc14af77c807736ddca061fbf395"),
    "\"upwind\"" => ("upwind", "4bd5f3c038828a93295ec5796abd280d113a509463d053459cc3bf7e2ab45f47"),
    ":sym" => (":sym", "3aac14729a53c26a719ec60c870b61361c4024bdce4535e50843c65340675f5d"),
    "'c'" => ("'c'", "895f17656ea9c815e192f49c20e7fe86d00cc9d865972f452d40b8c5324eef7a"),
    "nothing" => ("Nothing", "46b305f58f6c4e0e95564e7a68e7a115b8fb965be6475eed1bacfc41e58f50a0"),
    "(20, 15)" => ("(20, 15)", "514bb70e74cfc1790bdfc5b8d8a4fbfea0b256f466f2326c02d1be3a0fea1a5f"),
    "[0.1, 0.2]" => ("Float64[0.1, 0.2]", "a469708b22fbe28af0995e9988b83d84a563c316bf10431652d38fe1b6f97455"),
    "[1 2; 3 4]" => ("reshape(Int64[1, 3, 2, 4], (2, 2))", "9e38e6675c59d49d7271e7830a126b0cfdea61e8748d2a78707fc60481945611"),
    "PDEStudioCore.StaticArrays.SVector(1.0, 2.0)" => ("Float64[1.0, 2.0]", "4970cec9cb50d3bedb13ad4b9c01a93cd14ae4630b866d7d4bd5212ad40b370b"),
    "[PDEStudioCore.StaticArrays.SVector(0.25, 0.5), PDEStudioCore.StaticArrays.SVector(0.75, 0.5)]" => ("SVector{2, Float64}[Float64[0.25, 0.5], Float64[0.75, 0.5]]", "c46f274a56f9d84325b330d1a51349e2392a06dffdb6434f8c27f982787316ee"),
    "Dict(:a => 1, :b => \"x\")" => ("Dict{Symbol, Any}(:a => 1, :b => \"x\")", "df28499082a3d61b918c878545138425ee225b74d6796b1c8fa17d4ced12da7d"),
    "Float64" => ("Float64", "f9c477815d8c5b0c733c098aa8c84b35423f1382671902bd08ac5aebeb76f972"),
    "Val{:minmod}()" => ("Val{:minmod}()", "a83f2bdd193eb65af4370a744a468a44e864779dc801751e4f49875aa103351b"),
    "1:10" => ("Int64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]", "43fdb8ffb0eac9f04793a0c39697ec51f0a5d93c1877cb81727971776efa2ab5"),
    "Dict{Int, StCorpus.AbstractBC}(1 => StCorpus.Wall(1))" => ("Dict{Int64, AbstractBC}(1 => Wall(id=1))", "7f5923ac9fec95d39561f7292b1e5e61fb5cacdf56880d8f5f63b68e2f5d28e8"),
    "StCorpus.Limiter{:minmod}()" => ("Limiter{:minmod}", "5f8d994bff177ebc041f3bc2be8d9f128d7165ed959ae9732586c0213f0cd5e1"),
    "Val{Symbol(\"left.mode\")}()" => ("Val{Symbol(\"left.mode\")}()", "6d289c2679807b60f7764204f4243edf6bb33726f5067334e51a42443b0c5b97"),
    "Val{StCorpus.Matrix}()" => ("Val{Matrix}()", "918036f99fdc9ab0713acef15a59c6562a7e38c502a83ada7e44dec542f53b95"),
    "StCorpus.Domain(Val(:box), 0.0, x -> true, x -> 0, Dict{Int, StCorpus.AbstractBC}(1 => StCorpus.Wall(1)), 1.0)" => ("Domain(label=Val{:box}(), mins=0.0, bc_map=Dict{Int64, AbstractBC}(1 => Wall(id=1)))", "22188af0891847795bf1cb2e2d1855126237a6e387c24d5f47f062905bd72d58")
]

@testset "Parameter identity: the pinned corpus" begin
    include_string(Main, ST_CORPUS_PRELUDE)
    for (code, (text, hash)) in ST_CORPUS
        v = include_string(Main, code)
        @test val2str(get_clean_params(Dict(:v => v))[:v]) == text
        @test calculate_hash(Dict(:v => v)) == hash
    end
    script = "using PDEStudioCore; include_string(Main, $(repr(ST_CORPUS_PRELUDE))); " *
             "for c in $(repr(first.(ST_CORPUS))); println(calculate_hash(Dict(:v => include_string(Main, c)))); end"
    fresh = split(read(`$(Base.julia_cmd()) --project=$(Base.active_project()) -e $script`, String))
    @test fresh == [last(last(e)) for e in ST_CORPUS]   # (no `using StaticArrays`, no `using .StCorpus` there)
    # types by name only: `Base.Matrix` and a `Matrix` of one's own are one value; a configuration with both is refused
    @test calculate_hash(Dict(:v => Val{Base.Matrix}())) == calculate_hash(Dict(:v => Val{StCorpus.Matrix}()))
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_flat, :k => 1, :tag => Val{Base.Matrix}());
                           varied = create_varied_dict(:tag => Any[Val{Base.Matrix}(), Val{StCorpus.Matrix}()]))
    @test_throws r"stored alike" generate_tasks(cfg)
    # a domain is identified by what its `param_identity` names (label, bounds, conditions): not by its functions or its
    # derived volume
    bcs = Dict{Int, StCorpus.AbstractBC}(1 => StCorpus.Wall(1))
    box(label, f, vol = 1.0) = StCorpus.Domain(Val(label), 0.0, f, x -> 0, bcs, vol)
    @test calculate_hash(Dict(:domain => box(:box, x -> true))) == calculate_hash(Dict(:domain => box(:box, x -> x[1] < 0.5, 0.5)))
    @test calculate_hash(Dict(:domain => box(:box, x -> true))) != calculate_hash(Dict(:domain => box(:half, x -> x[1] < 0.5)))
    # strict: functions and values of types without a declared identity are refused, also nested
    @test_throws r":v is a function" calculate_hash(Dict(:v => sin))
    @test_throws r":v\[1\] has the type Matrix, which doesn't declare" calculate_hash(Dict(:v => [StCorpus.Matrix()]))
    @test_throws r"must return a NamedTuple" (@eval PDEStudioCore.param_identity(::StCorpus.Matrix) = 1; calculate_hash(Dict(:v => StCorpus.Matrix())))
end

@testset "Review fixes (#50)" begin
    @testset "a re-evaluation drops statistics that are no longer registered" begin
        st_fresh()
        src = joinpath(mktempdir(), "model.jl")
        model(c) = "st_src3_solver(p) = create_sim_data([0.0, 1.0], [1.0, 1.0], p)\nst_src3_reference(p) = _ -> $c\n"
        write(src, model(2.0))   # (reference A)
        cfg = SimulationConfig(create_param_dict(:sim_func_name => :st_src3_solver); reference = :st_src3_reference, sources = [src])
        stats() = load_sim_data(generate_tasks(cfg)[1]).stats
        old = PDEStudioCore.get_stat_registry()
        try
            set_stat_registry!(Dict(:l1error => :time))
            run_all_simulations(cfg; calculate_stats = true)
            write(src, model(4.0))   # (reference B)
            set_stat_registry!(Dict(:l2error => :time))   # (L1 unregistered, L2 registered: missing, so all are evaluated again)
            s = @test_logs (:warn, r"would be evaluated\s+again"s) match_mode = :any run_all_simulations(cfg; calculate_stats = true, dry_run = true)
            @test s.stats == Dict(:refreshed => 1) && stats()[:l1error][1] == 2.0   # (a dry run changes nothing)
            @test run_all_simulations(cfg; calculate_stats = true).stats == Dict(:refreshed => 1)
            @test !haskey(stats(), :l1error) && stats()[:l2error][1] ≈ sqrt(18)   # (the L1 of A is gone)
            register_stat!(:l1error, :time)
            @test run_all_simulations(cfg; calculate_stats = true).stats == Dict(:ran => 1) && stats()[:l1error][1] == 6.0
        finally
            set_stat_registry!(old)
        end
    end

    @testset "module names follow Julia's identifier syntax" begin
        @eval module ∇; export GradientTag; struct GradientTag end; end
        p = Dict(:t => Val{∇.GradientTag}())
        before = (val2str(p[:t]), calculate_hash(p))
        @eval using .∇: GradientTag
        @test before == (val2str(p[:t]), calculate_hash(p)) && before[1] == "Val{GradientTag}()"
    end
end
