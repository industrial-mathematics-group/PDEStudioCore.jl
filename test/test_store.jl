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
st_add_one(data) = (data.u = map(v -> v .+ 1, data.u); true)
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
    # a stored file of the parameters that isn't a usable run is replaced; a file of other parameters never
    p = st_params("retry")
    dest = st_save(p, 7)
    complete = joinpath(mktempdir(), "complete.jld2")
    cp(dest, complete)
    PDEStudioCore.JLD2.jldopen(f -> delete!(f, "raw"), dest, "a+")
    @test !does_sim_data_exist(p)
    @test (@test_logs (:info, r"isn't a usable run") match_mode = :any length(import_sim_data(complete))) == 1
    @test does_sim_data_exist(p) && st_stored(dest) == ("retry", 7.0)
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
    cfg(p) = SimulationConfig(p; reference = :st_double_reference, postprocess = :st_add_one)
    run_all_simulations(cfg(a); calculate_stats = true)
    d = load_sim_data(a)
    @test d.u[1][1] == 2.0 && d.stats[:l1error][1] == 2.0 && haskey(d.metadata, :postprocessed)   # (|1 - 2| twice, before +1)
    moved = mktempdir()
    mv(get_file_name(a), joinpath(moved, "a.jld2"))
    @test length(import_sim_data(moved; remove_keys = [:obsolete])) == 1
    d = load_sim_data(b)
    @test d.u[1][1] == 2.0 && d.stats[:l1error][1] == 2.0 && d.stats[:iterations][1] == 23.0 && haskey(d.metadata, :postprocessed)
    @test PDEStudioCore.JLD2.jldopen(f -> haskey(f, "evaluated_stats") && haskey(f, "evaluated_with_reference"), get_file_name(b), "r")
    s = run_all_simulations(cfg(b); calculate_stats = true)   # (nothing to do: not solved, evaluated or post-processed again)
    @test isempty(s.ran) && get(s.stats, :ran, 0) == 0 && get(s.postprocessing, :ran, 0) == 0 && load_sim_data(b).u[1][1] == 2.0
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
    s = run_all_simulations(SimulationConfig(p; reference = :st_popping_reference, postprocess = :st_add_one); calculate_stats = true)
    @test load_sim_data(p).u[1][1] == 11.0 && load_sim_data(other).u[1][1] == 80.0
    @test haskey(only(s.tasks), :offset) && get(s.postprocessing, :ran, 0) == 1
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
