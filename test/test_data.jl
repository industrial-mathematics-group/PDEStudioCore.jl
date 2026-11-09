PARAMS_CONV = create_param_dict(:N => 40, :scheme => "upwind", :cfl => 0.5, :test_mode => "conversion")

@testset "Conversions & caching" begin
    sim_base = advection_solver_1d(PARAMS_CONV)
    add_stat!(sim_base, :u_copy, deepcopy(sim_base.u), :all)
    add_stat!(sim_base, :profile, sim_base.u[:, end], :x)
    save_sim_data(sim_base; overwrite = true)
    @test does_sim_data_exist(PARAMS_CONV)
    nt = size(sim_base.u, 2)

    @testset "On-the-fly conversion (cache disabled)" begin
        enable_cache!(false)
        sim_L = load_sim_data(PARAMS_CONV, Val(:lagrangian))
        @test sim_L isa LSimData{2, 1, 1, Float64}
        @test !does_sim_data_exist(PARAMS_CONV, Val(:lagrangian))
        @test sim_L.stats[:Solution] === sim_L.u
        @test sim_L.stats[:u_copy] == sim_L.u        # full fields become particle fields
        @test length(sim_L.stats[:profile]) == nt    # spatial fields are repeated per step
        @test sim_L.x[1] === sim_L.x[end]            # stationary particles share their positions

        sim_E = load_sim_data(PARAMS_CONV, :eulerian, (20, 30))
        @test sim_E isa ESimData && size(sim_E.u) == (20, 30)
        @test size(sim_E.stats[:u_copy]) == (20, 30) && size(sim_E.stats[:profile]) == (20,)
        @test !does_sim_data_exist(PARAMS_CONV, Val(:eulerian), (20, 30))
        @test does_sim_data_exist(PARAMS_CONV, Val(:eulerian), size(sim_base.u))  # native resolution
    end

    @testset "Persistent conversion (cache enabled)" begin
        enable_cache!(true)
        try
            load_sim_data(PARAMS_CONV, Val(:lagrangian))
            @test does_sim_data_exist(PARAMS_CONV, Val(:lagrangian))
            @test "conv_L" in list_available_conversions(PARAMS_CONV)
            load_sim_data(PARAMS_CONV, Val(:eulerian), (25, 30))
            @test does_sim_data_exist(PARAMS_CONV, Val(:eulerian), (25, 30))
            @test "conv_E_25x30" in list_available_conversions(PARAMS_CONV)
            # Rewriting the raw data drops the now stale caches
            save_sim_data(sim_base; overwrite = true)
            @test isempty(list_available_conversions(PARAMS_CONV))
        finally
            enable_cache!(false)
        end
    end

    @testset "Scatter (Lagrangian -> Eulerian)" begin
        sim_L = load_sim_data(PARAMS_CONV, Val(:lagrangian))
        sim_E = convert_to_eulerian(sim_L, (30, nt))
        @test size(sim_E.u) == (30, nt) && sim_E.axes[2] == sim_L.t
        @test size(sim_E.stats[:u_copy]) == (30, nt)
        @test !any(v -> any(isnan, v), sim_E.u)  # every cell is reached
        # Scattering grid nodes back onto the same grid reproduces the data
        sim_same = convert_to_eulerian(sim_L, size(sim_base.u))
        @test all(isapprox.(first.(sim_same.u), first.(sim_base.u); atol = 1e-8))
        # Fewer time slices pick the nearest recorded snapshots
        sim_few = convert_to_eulerian(sim_L, (30, 5))
        @test size(sim_few.u) == (30, 5)
        @test sim_few.axes[2][1] == sim_L.t[1] && sim_few.axes[2][end] ≈ sim_L.t[end]
        @test_throws ArgumentError convert_to_eulerian(sim_L, (30,))
    end

    @testset "Derived datasets never replace the native data" begin
        sim_L = load_sim_data(PARAMS_CONV, Val(:lagrangian))
        @test_logs (:warn, r"not saved") match_mode = :any calculate_all_stats!(sim_L, nothing)
        @test load_sim_data(PARAMS_CONV) isa ESimData

        ref = generate_reference_simdata(exact_advection, PARAMS_CONV, sim_base.domain, (10, 5), :eulerian)
        @test_logs (:warn, r"not saved") match_mode = :any calculate_all_stats!(ref, exact_advection)
        @test size(load_sim_data(PARAMS_CONV).u) == size(sim_base.u)
        @test haskey(ref.stats, :mass)  # the statistics are still computed in memory

        # ... also at the native resolution, where representation, shape and parameters all match
        ref_native = generate_reference_simdata(exact_advection, PARAMS_CONV, sim_base.domain, size(sim_base.u), :eulerian)
        @test_logs (:warn, r"not saved") match_mode = :any calculate_all_stats!(ref_native, exact_advection)
        @test load_sim_data(PARAMS_CONV).u == sim_base.u
        # while the native dataset itself (with other statistics) is saved
        native = load_sim_data(PARAMS_CONV)
        calculate_all_stats!(native, exact_advection)
        @test haskey(load_sim_data(PARAMS_CONV).stats, :l1error)
    end

    @testset "Bookkeeping entries are written atomically" begin
        p = create_param_dict(:N => 20, :scheme => "upwind", :cfl => 0.5, :test_mode => "atomic")
        sim = advection_solver_1d(p)
        calculate_all_stats!(sim, exact_advection)
        file = get_file_name(p)
        flag() = load_sim_data(calculate_hash(get_clean_params(p))[1:12]; key = "evaluated_with_reference")
        @test flag() == true
        # Nothing to compute, only the flag changes: the file is replaced (new inode), not modified in place
        inode, size0 = stat(file).inode, filesize(file)
        calculate_all_stats!(sim)
        @test flag() == false && stat(file).inode != inode
        @test load_sim_data(p).u == sim.u && haskey(load_sim_data(p).stats, :l1error)
        # Flag updates don't rewrite the data (the file grows by little), and leave no temporary files behind
        for v in (true, false, true, false)
            PDEStudioCore._set_key!(file, "evaluated_with_reference", v)
        end
        @test filesize(file) <= size0 + 4096 && load_sim_data(p).u == sim.u
        @test !any(f -> endswith(f, ".tmp"), readdir(dirname(file)))
        # Entries of types this session doesn't know survive a bookkeeping update unchanged (another process
        # writes and reads them back)
        jl = Base.julia_cmd()
        proj = Base.active_project()
        foo_file = joinpath(mktempdir(), "foreign.jld2")
        def = "using PDEStudioCore; using PDEStudioCore.JLD2; struct ForeignEntry; a::Int; end"
        run(`$jl --project=$proj -e "$def; jldsave($(repr(foo_file)); foo = ForeignEntry(7))"`)
        PDEStudioCore._set_key!(foo_file, "evaluated_with_reference", true)
        @test success(`$jl --project=$proj -e "$def; x = load($(repr(foo_file)), \"foo\"); exit(x isa ForeignEntry && x.a == 7 ? 0 : 1)"`)
        # Here the type is unknown, so rewriting the data warns about the entry; also when the unknown type is
        # only an element type (a type defined in an anonymous module can't be found again by JLD2)
        @test PDEStudioCore._is_reconstructed(PDEStudioCore.JLD2.load(foo_file, "foo"))
        anon = Module()
        Core.eval(anon, :(struct Hidden; a::Int; end))
        hidden_file = joinpath(mktempdir(), "hidden.jld2")
        PDEStudioCore.JLD2.jldsave(hidden_file; v = [Base.invokelatest(anon.Hidden, 1)])
        @test PDEStudioCore._is_reconstructed(PDEStudioCore.JLD2.load(hidden_file, "v"))
        @test !PDEStudioCore._is_reconstructed([1.0, 2.0]) && !PDEStudioCore._is_reconstructed(Dict(:a => 1))
        # ... also a type stored as a value (JLD2.UnknownType) and values inside untyped containers, named in the warning
        PDEStudioCore.JLD2.jldsave(hidden_file; t = anon.Hidden, anyv = Any[1, Base.invokelatest(anon.Hidden, 2)],
                                   d = Dict{Symbol, Any}(:h => anon.Hidden), nested = Any[Any[(1, anon.Hidden)]])
        for k in ("t", "anyv", "d", "nested")
            found = PDEStudioCore._reconstructed_type(PDEStudioCore.JLD2.load(hidden_file, k))
            @test found !== nothing && occursin("Hidden", found)
        end
        @test !PDEStudioCore._is_reconstructed(Any[1, "a", (2, :b), Float64]) &&
              !PDEStudioCore._is_reconstructed(Dict{Symbol, Any}(:a => [1.0], :T => Float32))
        # ... also untyped containers inside typed ones, NamedTuples, pairs, and the values of a large dictionary
        H = Base.invokelatest(anon.Hidden, 3)
        big = Dict{Symbol, Any}(Symbol("k", i) => i for i in 1:10^4)
        big[:z] = H
        PDEStudioCore.JLD2.jldsave(hidden_file; vv = [Any[H]], dd = Dict("run" => Dict{Symbol, Any}(:h => anon.Hidden)),
                                   nt = (a = 1, b = Any[H]), pr = :p => Any[H], big = big, st = Set{Any}([H]),
                                   sd = Dict{Symbol, Any}(:s => Set{Any}([H])))
        for k in ("vv", "dd", "nt", "pr", "big", "st", "sd")
            @test PDEStudioCore._is_reconstructed(PDEStudioCore.JLD2.load(hidden_file, k))
        end
        # the cost is bounded per entry (nested untyped data with 8·10^5 leaves took seconds and GiBs on every rewrite)
        nested = Any[Any[Any[Any[0.0 for _ in 1:30] for _ in 1:30] for _ in 1:30] for _ in 1:30]
        PDEStudioCore._reconstructed_type(nested)
        @test @elapsed(PDEStudioCore._reconstructed_type(nested)) < 2   # (milliseconds; it took seconds)
        # ... also for many containers of a wide element type: whether a type can hide other types is checked once per
        # type (it was checked again for every container), so the check records one entry per distinct type
        wide = Any[Dict{Symbol, NTuple{8, NTuple{8, Float64}}}() for _ in 1:10^4]
        state = (budget = Ref(PDEStudioCore._RECONSTRUCTED_VISITS), seen = Dict{Any, Union{Nothing, String}}(),
                 hides = Dict{Any, Bool}())
        @test isnothing(PDEStudioCore._reconstructed_type(wide, 4, state)) && length(state.hides) == 3
        # the pattern is anchored: a type `Reconstructed` of a module whose name ends in JLD2 is no reconstruction
        M = Module(:MyJLD2)
        Core.eval(M, :(struct Reconstructed end))
        @test !PDEStudioCore._is_reconstructed(Base.invokelatest(M.Reconstructed))
        # the warning on a rewrite names the missing type
        dest = joinpath(mktempdir(), "dest.jld2")
        PDEStudioCore.JLD2.jldopen(dest, "w") do d
            PDEStudioCore.JLD2.jldopen(hidden_file, "r") do src
                @test_logs (:warn, r"contains a type that isn't loaded.*Hidden") match_mode = :any PDEStudioCore._copy_entry!(d, src, "vv")
            end
        end
        # A symlinked data file stays a symlink, and its target is updated
        link = foo_file * ".link.jld2"
        symlink(foo_file, link)
        PDEStudioCore._set_key!(link, "evaluated_with_reference", false)
        @test islink(link) && PDEStudioCore.JLD2.load(foo_file, "evaluated_with_reference") == false

        # Unchanged entries don't touch the file at all
        inode = stat(file).inode
        calculate_all_stats!(sim)
        @test stat(file).inode == inode
    end

    @testset "Resampling keeps non-uniform axes it does not resample" begin
        x = collect(range(0.0, 1.0, length = 11))
        t = [0.0, 0.1, 0.3, 0.7, 1.5]                      # adaptive time steps
        s = create_sim_data(x, [SVector(xi + ti) for xi in x, ti in t], t, create_param_dict(:case => "nonuniform"))
        add_stat!(s, :series, collect(1.0:5.0), :time)
        r = resample_eulerian(s, (21, 5))
        @test r.axes[2] == t && r.stats[:series] == s.stats[:series]
        @test r.u[end, 3] ≈ s.u[end, 3]
        r2 = resample_eulerian(s, (11, 3))                 # time is resampled: uniform, nearest snapshot
        @test r2.axes[2] ≈ [0.0, 0.75, 1.5] && length(r2.stats[:series]) == 3
    end

    @testset "Static data" begin
        x = collect(range(0.0, 1.0, length = 6))
        y = collect(range(0.0, 2.0, length = 5))
        s = create_sim_data((x, y), [SVector(xi + yi) for xi in x, yi in y], create_param_dict(:case => "static-conv"))
        L = convert_to_lagrangian(s)
        @test L isa LSimData{2, 2, 1, Float64} && length(L.t) == 1 && length(L.x[1]) == 30
        E = convert_to_eulerian(L, (6, 5))
        @test all(isapprox.(first.(E.u), first.(s.u); atol = 1e-8))
        R = resample_eulerian(s, (11, 9))
        @test size(R.u) == (11, 9) && R.u[1, 1] ≈ s.u[1, 1] && R.u[end, end] ≈ s.u[end, end]
        @test resample_eulerian(s, (6, 5)) === s
    end
end

@testset "Data health checking" begin
    sim_E = load_sim_data(PARAMS_CONV)
    df_E = check_data(sim_E)
    @test df_E isa DataFrame && size(df_E, 1) == 1
    @test names(df_E) == ["Time", "C1_Min", "C1_Max", "C1_Mean", "C1_NaNs"]
    @test df_E.C1_NaNs[1] == 0.0
    df_steps = check_data(sim_E; per_step = true)
    @test size(df_steps, 1) == size(sim_E.u, 2) && df_steps.Time == sim_E.axes[2]

    sim_L = load_sim_data(PARAMS_CONV, Val(:lagrangian))
    df_L = check_data(sim_L)
    @test df_L isa DataFrame && size(df_L, 1) == length(sim_L.t)
end

@testset "Data management: deletion" begin
    delete_params = create_param_dict(:N => 9, :scheme => "upwind", :cfl => 0.5, :test_flag => "delete_me")
    keep_params = create_param_dict(:N => 9, :scheme => "upwind", :cfl => 0.5, :test_flag => "keep_me")
    save_sim_data(advection_solver_1d(delete_params); overwrite = true)
    save_sim_data(advection_solver_1d(keep_params); overwrite = true)
    @test does_sim_data_exist(delete_params) && does_sim_data_exist(keep_params)

    # find_sim_data: any subset of the parameters, string or symbol keys, newest first
    found = find_sim_data(Dict("test_flag" => "delete_me"); verbose = false)
    @test found == [get_file_name(delete_params)]
    found_n = find_sim_data(Dict(:N => 9, :scheme => "upwind"); verbose = false)
    @test Set(found_n) ⊇ Set([get_file_name(delete_params), get_file_name(keep_params)])
    @test issorted(mtime.(found_n); rev = true)
    @test isempty(find_sim_data(Dict(:N => 9, :test_flag => "no such flag"); verbose = false))
    @test length(find_sim_data(Dict(); verbose = false)) == length(PDEStudioCore._data_files())
    io = IOBuffer()
    @test find_sim_data(Dict(:test_flag => "delete_me"); io = io) == found
    listing = String(take!(io))
    @test startswith(listing, "1 data file with test_flag = delete_me:")
    @test occursin(basename(found[1]), listing) && occursin("N = 9", listing) && !occursin("test_flag", split(listing, '\n')[2])
    io = IOBuffer(); find_sim_data(Dict(:N => -1); io = io)
    @test startswith(String(take!(io)), "0 data files with N = -1.")

    @test_throws ArgumentError delete_sim_data(Dict())  # would match every file
    @test length(delete_sim_data(Dict(:test_flag => "delete_me"); dry_run = true)) == 1
    @test does_sim_data_exist(delete_params)

    deleted = delete_sim_data(Dict(:N => 9, :test_flag => "delete_me"))
    @test length(deleted) == 1
    @test !does_sim_data_exist(delete_params) && does_sim_data_exist(keep_params)
end

@testset "Data management: rehash" begin
    params_target = create_param_dict(:N => 10, :scheme => "upwind", :cfl => 0.5, :target => true, :obsolete => "delete_me")
    params_ignore = create_param_dict(:N => 11, :scheme => "upwind", :cfl => 0.5, :target => false, :obsolete => "keep_me")
    save_sim_data(advection_solver_1d(params_target); overwrite = true)
    save_sim_data(advection_solver_1d(params_ignore); overwrite = true)
    file_target_old = get_file_name(params_target)
    file_ignore_old = get_file_name(params_ignore)

    renamed = rehash_sim_data(joinpath(get_save_path(), "data"); delete_old = true,
                              filter_pairs = Dict(:target => true), remove_keys = [:obsolete])
    @test length(renamed) == 1 && first(renamed[1]) == file_target_old
    @test isfile(file_ignore_old) && !isfile(file_target_old)

    params_new = create_param_dict(:N => 10, :scheme => "upwind", :cfl => 0.5, :target => true)
    @test does_sim_data_exist(params_new)
    sim_rehashed = load_sim_data(params_new)
    @test !haskey(sim_rehashed.params, :obsolete) && sim_rehashed.params[:target] == true

    # A symlinked file whose hash changes: the rehashed data is a regular file, the link is removed with a warning,
    # and its target (which may be shared) is kept
    p_link = create_param_dict(:N => 12, :scheme => "upwind", :cfl => 0.5, :obsolete => "x", :test_mode => "link")
    save_sim_data(advection_solver_1d(p_link); overwrite = true)
    linked = get_file_name(p_link)
    target = joinpath(mktempdir(), basename(linked))
    mv(linked, target)
    symlink(target, linked)
    @test_logs (:warn, r"is a symlink.*is not deleted"s) match_mode = :any rehash_sim_data(linked; remove_keys = [:obsolete])
    @test isfile(target) && !ispath(linked)
    p_new = create_param_dict(:N => 12, :scheme => "upwind", :cfl => 0.5, :test_mode => "link")
    @test does_sim_data_exist(p_new) && !islink(get_file_name(p_new))
end

@testset "Stored data info without loading" begin
    sim = load_sim_data(PARAMS_CONV)
    info = get_sim_data_info(PARAMS_CONV)
    @test info.kind === :eulerian && info.shape == size(sim.u) && info.dim_keys == sim.domain.dim_keys
    @test info.time_dim === :t && info.n_steps == length(sim.axes[end]) && info.path == get_file_name(PARAMS_CONV)
    # particles: shape (time steps, particles)
    pl = create_param_dict(:N => 5, :test_mode => "info_lagrangian")
    t = [0.0, 0.5, 1.0]
    save_sim_data(create_sim_data([[SVector(i + ti) for i in 1.0:5.0] for ti in t], [[SVector(1.0) for _ in 1:5] for _ in t],
                                  t, pl); overwrite = true)
    li = get_sim_data_info(pl)
    @test li.kind === :lagrangian && li.shape == (3, 15) && li.time_dim === :t && li.n_steps == 3
    # static grid data
    ps = create_param_dict(:N => 4, :test_mode => "info_static")
    save_sim_data(create_sim_data(collect(0.0:0.25:0.75), [SVector(1.0) for _ in 1:4], ps); overwrite = true)
    si = get_sim_data_info(ps)
    @test si.kind === :eulerian && si.time_dim === nothing && si.n_steps == 0 && si.dim_keys == (:x,)
    # files written before the axes were part of the metadata: read from the data
    JLD2 = PDEStudioCore.JLD2
    for p in (PARAMS_CONV, pl)
        path = get_file_name(p)
        entries = JLD2.jldopen(f -> Dict(k => f[k] for k in keys(f) if !(k in ("dim_keys", "time_dim"))), path, "r")
        rm(path)
        JLD2.jldopen(path, "w") do f
            for (k, v) in entries
                f[k] = v
            end
        end
        @test !JLD2.jldopen(f -> haskey(f, "dim_keys"), path, "r")
    end
    @test get_sim_data_info(PARAMS_CONV) == info && get_sim_data_info(pl) == li
    # ... also when an older file holds user metadata under these names: the axes come from the data
    path = get_file_name(PARAMS_CONV)
    JLD2.jldopen(path, "a+") do f
        f["dim_keys"] = ["user"]
        f["time_dim"] = "user value"
    end
    @test get_sim_data_info(PARAMS_CONV) == info
    # ... or that look like axes but not like what this version writes (time axis not last, repeated names, no
    # "time_dim" entry)
    for (keys_, tdim) in (([:t, :x], :t), ([:x, :x], nothing), ([:missing], nothing))
        JLD2.jldopen(path, "a+") do f
            delete!(f, "dim_keys"); delete!(f, "time_dim")
            f["dim_keys"] = keys_
            isnothing(tdim) || (f["time_dim"] = tdim)
        end
        @test get_sim_data_info(PARAMS_CONV) == info
    end
    # the axes this version writes are read without loading the data: also found in a copy without "raw"
    save_sim_data(load_sim_data(PARAMS_CONV); overwrite = true, verbose = false)
    path = get_file_name(PARAMS_CONV)
    JLD2.jldopen(f -> delete!(f, "raw"), path, "a+")
    @test get_sim_data_info(PARAMS_CONV) == info
    @test_throws SimFileNotFoundError get_sim_data_info(create_param_dict(:N => 1, :test_mode => "info_missing"))
end

@testset "Output formatting & manual loading" begin
    params_E = create_param_dict(:N => 25, :scheme => "upwind", :cfl => 0.5, :test_id => "format_E")
    sim_E = advection_solver_1d(params_E)
    save_sim_data(sim_E; overwrite = true)
    sim_L = particle_solver_1d(create_param_dict(:N => 10, :v => 1.5, :test_id => "format_L"))

    @testset "Clean parameter processing & printing" begin
        clean_from_dict = get_clean_params(params_E)
        @test clean_from_dict isa Dict{Symbol, Any} && clean_from_dict == get_clean_params(sim_E)
        @test clean_from_dict[:test_id] == "format_E"
        pipe = Pipe()
        printed = redirect_stdout(pipe) do
            print_clean_params(sim_E)
        end
        close(pipe.in)
        out = read(pipe, String)
        @test printed == clean_from_dict
        @test occursin("Cleaned Parameters", out) && occursin("test_id => format_E", out) && occursin("scheme => upwind", out)
    end

    @testset "REPL display" begin
        out_E = repr("text/plain", sim_E)
        for label in ("ESimData", "Time (T)", "Space", "Grid Size", "Parameters", "Statistics", "Solution")
            @test occursin(label, out_E)
        end
        out_L = repr("text/plain", sim_L)
        for label in ("LSimData", "Time (T)", "Space", "Particles", "Parameters", "Statistics")
            @test occursin(label, out_L)
        end
        @test startswith(repr(sim_E), "ESimData{2, 1, 1, Float64}(25×")
        @test startswith(repr(sim_L), "LSimData{2, 1, 1, Float64}(3 steps")
    end

    @testset "Manual loading by hash prefix" begin
        prefix = calculate_hash(params_E)[1:8]
        entries = load_sim_data(prefix)
        @test entries["raw"] isa ESimData && entries["raw"].params[:test_id] == "format_E"
        @test load_sim_data(prefix; key = "raw") isa ESimData
        # Extra metadata cannot clobber the file layout
        @test_throws ArgumentError save_sim_data(sim_E; overwrite = true, metadata = Dict("raw" => 1))
        @test_throws ArgumentError save_sim_data(sim_E; overwrite = true, metadata = Dict(:conv_L => 1))
        save_sim_data(sim_E; overwrite = true, metadata = Dict(:note => "kept"))
        @test load_sim_data(prefix; key = "note") == "kept"
        @test_throws SimFileNotFoundError load_sim_data("00000000000000000")
        @test_throws SimFileNotFoundError load_sim_data("2026-10")  # timestamps are not matched
    end
end

# Runs `f` with a fresh, empty save path (so tests can look at the whole data directory)
function with_fresh_save_path(f)
    old = get_save_path()
    set_save_path!(mktempdir())
    try
        f()
    finally
        set_save_path!(old)
    end
end

@testset "Data management: directory index" begin
    with_fresh_save_path() do
        p = create_param_dict(:N => 8, :test_mode => "index")
        save_sim_data(advection_solver_1d(p); verbose = false)
        file = get_file_name(p)
        h = PDEStudioCore._filename_hash(basename(file))
        @test PDEStudioCore._files_with_hash(h) == [file] && does_sim_data_exist(p)
        # files added and removed by others (another process, the shell) are seen, also right after a listing
        older = joinpath(dirname(file), "2020-01-01_00-00-00_000_" * h * ".jld2")
        cp(file, older); touch(file)
        @test PDEStudioCore._files_with_hash(h) == [file, older]   # newest first
        rm(file)
        @test PDEStudioCore._files_with_hash(h) == [older] && get_file_name(p) == older
        # ... and if the directory's time didn't change long after a listing (a file system caching it): a missing
        # hash is looked up again, and a listed file is checked to exist
        idx = PDEStudioCore._data_index()
        fake = "f" ^ 64
        added = joinpath(dirname(older), "2020-01-01_00-00-00_000_" * fake * ".jld2")
        cp(older, added)
        idx.stamp = mtime(dirname(older))
        idx.listed = idx.stamp + 2 * PDEStudioCore._INDEX_RACY   # (as if listed long after)
        @test PDEStudioCore._files_with_hash(fake) == [added]
        idx = PDEStudioCore._data_index()
        rm(older)
        idx.stamp = mtime(dirname(added))
        idx.listed = idx.stamp + 2 * PDEStudioCore._INDEX_RACY   # (as if listed long after)
        @test isempty(PDEStudioCore._files_with_hash(h)) && !does_sim_data_exist(p)
        # writers update it
        save_sim_data(advection_solver_1d(p); verbose = false)
        @test does_sim_data_exist(p) && length(PDEStudioCore._data_files()) == 2
        delete_sim_data(Dict(:test_mode => "index"))
        @test !does_sim_data_exist(p) && isempty(PDEStudioCore._data_files())   # (the copy has the same parameters)
        # another save path has another index
        set_save_path!(mktempdir())
        @test isempty(PDEStudioCore._data_files())
    end
end

@testset "Data management: file format version" begin
    JLD2 = PDEStudioCore.JLD2
    with_fresh_save_path() do
        p = create_param_dict(:N => 8, :scheme => "upwind", :cfl => 0.5, :sim_func_name => :counting_solver,
                              :test_mode => "format")
        save_sim_data(advection_solver_1d(p); verbose = false)
        path = get_file_name(p)
        @test JLD2.jldopen(f -> f["format_version"], path, "r") == PDEStudioCore._FORMAT_VERSION
        @test upgrade_sim_data(path) == Dict(:upgraded => String[], :current => [path], :unreadable => String[])
        # a file of 0.4 (no version, no axes): still read; upgrade_sim_data adds what it lacks
        JLD2.jldopen(path, "a+") do f
            delete!(f, "format_version"); delete!(f, "dim_keys"); delete!(f, "time_dim")
        end
        @test does_sim_data_exist(p) && JLD2.jldopen(PDEStudioCore._format_version, path, "r") == 1
        @test upgrade_sim_data(path; dry_run = true)[:upgraded] == [path]
        @test !JLD2.jldopen(f -> haskey(f, "format_version"), path, "r")
        @test upgrade_sim_data()[:upgraded] == [path]
        @test JLD2.jldopen(f -> (f["format_version"], f["dim_keys"], f["time_dim"]), path, "r") ==
              (PDEStudioCore._FORMAT_VERSION, [:x, :t], :t)
        @test upgrade_sim_data()[:current] == [path]
        # a file of an earlier version (only the data): upgraded by the pipeline instead of recomputed
        sim = load_sim_data(p)
        rm(path)
        JLD2.jldopen(f -> (f["raw"] = sim), path, "w")
        SOLVER_CALLS[] = 0
        s = @test_logs (:info, r"Upgraded") match_mode = :any run_all_simulations(SimulationConfig(p))
        @test length(s.cached) == 1 && SOLVER_CALLS[] == 0
        @test JLD2.jldopen(PDEStudioCore._format_version, path, "r") == PDEStudioCore._FORMAT_VERSION
        @test load_sim_data(p).u == sim.u
        # ... unless its data doesn't load as a dataset: recomputed
        rm(path)
        JLD2.jldopen(f -> (f["raw"] = "not a dataset"), path, "w")
        @test upgrade_sim_data(path)[:unreadable] == [path]
        @test length(run_all_simulations(SimulationConfig(p)).ran) == 1 && SOLVER_CALLS[] == 1
        @test_throws ArgumentError upgrade_sim_data(joinpath(get_save_path(), "no such file.jld2"))
    end
end

@testset "Data management: provenance" begin
    JLD2 = PDEStudioCore.JLD2
    with_fresh_save_path() do
        p = create_param_dict(:N => 8, :test_mode => "provenance")
        save_sim_data(advection_solver_1d(p); verbose = false)
        prov = JLD2.jldopen(f -> f["provenance"], get_file_name(p), "r")
        @test prov["pdestudiocore"] == string(pkgversion(PDEStudioCore)) && prov["julia"] == string(VERSION)
        @test prov["host"] == gethostname() && prov["threads"] == Threads.nthreads() && !haskey(prov, "solver")
        # data a solver made: the solver and its wall time
        q = create_param_dict(:N => 8, :scheme => "upwind", :cfl => 0.5, :sim_func_name => :advection_solver_1d,
                              :test_mode => "provenance")
        cfg = SimulationConfig(q; postprocess = :keep_post)
        run_all_simulations(cfg)
        path = get_file_name(q)
        prov = JLD2.jldopen(f -> f["provenance"], path, "r")
        @test prov["solver"] == "advection_solver_1d" && prov["solver_module"] == "Main" && !haskey(prov, "solver_version")
        @test prov["wall_time"] isa Float64 && prov["wall_time"] >= 0
        # kept by rewrites of the same data (post-processing, statistics), replaced with new data
        run_all_simulations(cfg; calculate_stats = true, force_postprocess = true)
        @test JLD2.jldopen(f -> f["provenance"], get_file_name(q), "r") == prov
        run_all_simulations(cfg; force_overwrite = true)
        @test JLD2.jldopen(f -> f["provenance"]["created"], get_file_name(q), "r") != prov["created"]
        # entries of the layout and the record are reserved
        for key in ("provenance", "postprocessed", "format_version", :provenance)
            @test_throws ArgumentError save_sim_data(advection_solver_1d(p); overwrite = true, metadata = Dict(key => 1))
            @test_throws ArgumentError run_smart_simulation(advection_solver_1d, p; metadata = Dict(key => 1))
        end
        # the git commit, read from the repository's files
        repo = mktempdir()
        sha = "0123456789abcdef0123456789abcdef01234567"
        mkpath(joinpath(repo, ".git", "refs", "heads")); mkpath(joinpath(repo, "sub", "dir"))
        write(joinpath(repo, ".git", "HEAD"), "ref: refs/heads/main\n")
        write(joinpath(repo, ".git", "refs", "heads", "main"), sha * "\n")
        @test PDEStudioCore._git_commit(joinpath(repo, "sub", "dir")) == sha
        rm(joinpath(repo, ".git", "refs", "heads", "main"))
        write(joinpath(repo, ".git", "packed-refs"), "# pack-refs with: peeled\n$sha refs/heads/main\n")
        @test PDEStudioCore._git_commit(repo) == sha
        write(joinpath(repo, ".git", "HEAD"), reverse(sha) * "\n")   # detached
        @test PDEStudioCore._git_commit(repo) == reverse(sha)
        # a worktree: ".git" is a file pointing to its git dir, which shares the refs of the main repository
        wt = mktempdir()
        wtgit = joinpath(repo, ".git", "worktrees", "wt")
        mkpath(wtgit)
        write(joinpath(wtgit, "HEAD"), "ref: refs/heads/main\n"); write(joinpath(wtgit, "commondir"), "../..\n")
        write(joinpath(wt, ".git"), "gitdir: $wtgit\n")
        @test PDEStudioCore._git_commit(wt) == sha
    end
end

@testset "Data management: tidy and table" begin
    with_fresh_save_path() do
        @test tidy_sim_data() == (duplicates = String[], temp_files = String[])
        t = sim_data_table()
        @test size(t, 1) == 0 && names(t)[1:3] == ["file", "created", "size_mb"]
        p = create_param_dict(:N => 8, :scheme => "upwind", :cfl => 0.5, :sim_func_name => :advection_solver_1d,
                              :test_mode => "tidy")
        run_all_simulations(SimulationConfig(p; varied = Dict(:N => [8, 9]), postprocess = :count_post); calculate_stats = true)
        file = get_file_name(p)
        dir = dirname(file)
        h = PDEStudioCore._filename_hash(basename(file))
        older = joinpath(dir, "2020-01-01_00-00-00_000_" * h * ".jld2")
        cp(file, older); touch(file)
        tmp = PDEStudioCore._tmp_path(file)
        write(tmp, "an unfinished write")
        write(joinpath(dir, "notes.tmp"), "not ours")
        # unfinished writes are removed once they are old enough
        @test tidy_sim_data(dry_run = true) == (duplicates = [older], temp_files = String[])
        @test tidy_sim_data(dry_run = true, min_tmp_age = 0) == (duplicates = [older], temp_files = [tmp])
        @test isfile(older) && isfile(tmp)

        # the table: one row per file, newest first
        t = sim_data_table()
        row(name) = only(findall(==(name), t.file))
        @test size(t, 1) == 3 && issorted(mtime.(joinpath.(dir, t.file)); rev = true)
        @test t.created[row(basename(older))] == PDEStudioCore.DateTime(2020) && all(==(:eulerian), t.kind)
        @test t.shape[row(basename(file))] == size(load_sim_data(p).u) && all(==(PDEStudioCore._FORMAT_VERSION), t.format_version)
        @test all(s -> :mass in s, t.stats) && all(==("count_post"), t.postprocessed) && all(==("advection_solver_1d"), t.solver)
        @test all(x -> x isa Float64, t.wall_time) && sort(unique(t.N)) == [8, 9] && all(==("tidy"), t.test_mode)
        @test size(sim_data_table(Dict(:N => 9)), 1) == 1
        save_sim_data(advection_solver_1d(create_param_dict(:N => 5, :M => 3, :test_mode => "table")); verbose = false)
        t = sim_data_table()
        @test size(t, 1) == 4 && ismissing(t.wall_time[1]) && ismissing(t.postprocessed[1]) && ismissing(t.solver[1])
        @test t.M[1] == 3 && all(ismissing, t.M[2:end]) && ismissing(t.scheme[1])

        removed = tidy_sim_data(min_tmp_age = 0)
        @test removed == (duplicates = [older], temp_files = [tmp])
        @test !isfile(older) && !isfile(tmp) && isfile(joinpath(dir, "notes.tmp")) && does_sim_data_exist(p)
        @test size(sim_data_table(), 1) == 3
    end
end
