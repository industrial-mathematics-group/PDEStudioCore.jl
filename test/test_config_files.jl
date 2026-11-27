# Configuration files: parameter literals, the configuration a file ends with, included files and source bundles

@enum ConfigFileColour cf_red cf_blue
struct ConfigFileWall; id::Int; end
PDEStudioCore.@param_struct ConfigFileWall

@testset "Configuration files" begin
    @testset "param_literal reads back with value and type" begin
        data = Any[1, 1.5, 1.5f0, Float16(2), true, 'c', :sym, "abc", "1e3", "Float64", " padded ", "", "a, b => 1",
                   "x\ny", nothing, missing, (1.5f0, 2), (nothing, 1.0), Any[nothing, :minmod], Any[missing, 1],
                   :a => 1, :a => (:b => 2), (:a => 1) => 2, [:a => 1, :b => 2], Dict(:a => 1.5f0), Dict(:a => nothing),
                   Dict("x" => [1.0, 2.0]), SVector(1.0, 2.0), [SVector(1.0f0, 2.0f0)], [1.0 2.0; 3.0 4.0], Float64[],
                   Any[1.5f0, "a"], Val(1), Float64]
        for v in data
            text = param_literal(v)
            @test text isa String
            back = str2val(text)
            @test isequal(back, v) && typeof(back) == typeof(v)
            @test !is_param_object(v)
        end
        # ranges read back as vectors of the same values (and the same identity)
        @test isequal(str2val(param_literal(0:0.5:1)), [0.0, 0.5, 1.0]) && !is_param_object(0:0.5:1)
        # the literal keeps what the identity text loses, and the identity (the hash) is the one of the value
        @test param_literal(1.5f0) == "1.5f0" && param_literal("1e3") == "\"1e3\"" && param_literal("abc") == "abc"
        @test param_literal(:a => 1) == ":a => 1" && param_literal(nothing) == "nothing"
        hash_of(v) = calculate_hash(get_clean_params(Dict{Symbol, Any}(:p => v, :sim_func_name => :f)))
        for v in Any[1.5f0, (1.5f0, 2), :a => 1, Dict(:a => 1.5f0), SVector(1.0, 2.0), "1e3", [1.0 2.0; 3.0 4.0], 0:0.5:1]
            @test hash_of(str2val(param_literal(v))) == hash_of(v)
        end
        # objects: their literal is their identity text, which doesn't read back as the value
        for v in Any[ConfigFileWall(1), cf_red, [ConfigFileWall(1), ConfigFileWall(2)], Dict(:a => ConfigFileWall(1)),
                     (1, ConfigFileWall(2)), sin]
            @test is_param_object(v)
        end
        @test param_literal(ConfigFileWall(1)) == val2str(ConfigFileWall(1)) == "ConfigFileWall(id=1)"
    end

    body = "SimulationConfig(create_param_dict(:N => 12, :sim_func_name => :upwind_solver), " *
           "create_method_dict(:m => create_param_dict()), [:m])"

    @testset "to_simulation_config: a configuration or a function without arguments" begin
        config = eval(Meta.parse(body))
        @test to_simulation_config(config, "x") === config
        @test to_simulation_config(() -> config, "x") === config
        zero_arg_config_fn() = config
        @test to_simulation_config(zero_arg_config_fn, "x") === config
        optional(N = 12) = config
        keyword(; N = 12) = config
        positional(N) = config
        returns_nothing() = nothing
        for (f, msg) in ((optional, "takes arguments"), (keyword, "takes arguments"), (positional, "takes arguments"),
                         (returns_nothing, "returned nothing"), (1, "must end with a SimulationConfig"),
                         (nothing, "returned nothing"))
            err = try to_simulation_config(f, "cfg.jl"); nothing catch e; e end
            @test err isa ArgumentError && occursin(msg, err.msg) && occursin("cfg.jl", err.msg)
        end
        err = try to_simulation_config(optional, "cfg.jl"); nothing catch e; e end
        @test occursin("stay until Julia restarts", err.msg)
        @eval function config_file_no_methods end
        err = try to_simulation_config(config_file_no_methods, "cfg.jl"); nothing catch e; e end
        @test err isa ArgumentError && occursin("no methods", err.msg)
    end

    # a configuration in `dir`: cfg.jl includes lib/helper.jl, which includes lib/deep/inner.jl; solvers.jl is listed
    function write_config(dir; extra_line = "")
        mkpath(joinpath(dir, "lib", "deep"))
        write(joinpath(dir, "lib", "deep", "inner.jl"), "config_file_inner() = 3\n")
        write(joinpath(dir, "lib", "helper.jl"), "include(\"deep/inner.jl\")\nconfig_file_helper() = config_file_inner() + 1\n")
        write(joinpath(dir, "solvers.jl"), "config_file_listed() = 7\n")
        write(joinpath(dir, "cfg.jl"), """
            include("lib/helper.jl")
            $extra_line
            SimulationConfig(create_param_dict(:N => config_file_helper(), :sim_func_name => :upwind_solver),
                             create_method_dict(:m => create_param_dict()), [:m];
                             sources = [@__FILE__, joinpath(@__DIR__, "solvers.jl")])
            """)
        return joinpath(dir, "cfg.jl")
    end

    @testset "load_config_file: the file is the last source, the included files are reported" begin
        dir = mktempdir()
        cfg = write_config(dir)
        included = String[]
        config = load_config_file(cfg; included = included)
        @test config.shared[:N] == 4
        # the listed sources, the file last (it listed itself first); the helpers it includes are no sources
        @test config.sources == [joinpath(dir, "solvers.jl"), cfg]
        @test included == [cfg, joinpath(dir, "lib", "helper.jl"), joinpath(dir, "lib", "deep", "inner.jl")]
        @test load_config_file(cfg).sources == config.sources   # (without the list, too)
        # a function without arguments, and what isn't a configuration
        write(joinpath(dir, "fn.jl"), "() -> $body\n")
        @test load_config_file(joinpath(dir, "fn.jl")).shared[:N] == 12
        write(joinpath(dir, "bad.jl"), "config_file_optional(N = 12) = $body\nconfig_file_optional\n")
        err = try load_config_file(joinpath(dir, "bad.jl")); nothing catch e; e end
        @test err isa ArgumentError && occursin("bad.jl", err.msg) && occursin("takes arguments", err.msg)
        @test_throws ArgumentError load_config_file(joinpath(dir, "missing.jl"))
        # into another module
        m = @eval module $(gensym(:ConfigFileModule)); using PDEStudioCore; end
        load_config_file(cfg; mod = m)
        @test isdefined(m, :config_file_helper)
    end

    @testset "include_sources: the files that ran, and nothing from outside `within`" begin
        dir, outside = mktempdir(), mktempdir()
        cfg = write_config(dir)
        files = include_sources([joinpath(dir, "solvers.jl"), cfg])
        @test files == [joinpath(dir, "solvers.jl"), cfg, joinpath(dir, "lib", "helper.jl"), joinpath(dir, "lib", "deep", "inner.jl")]
        @test include_sources([cfg]; within = dir) == files[2:end]
        @test_throws ArgumentError include_sources([joinpath(dir, "missing.jl")])
        @test_throws ArgumentError include_sources([cfg, cfg])
        # a file outside the folder is refused before it runs, wherever the include is
        write(joinpath(outside, "out.jl"), "global config_file_outside_ran = true\n")
        @eval global config_file_outside_ran = false
        cfg = write_config(dir; extra_line = "include($(repr(joinpath(outside, "out.jl"))))")
        unwrap(e) = e isa LoadError ? unwrap(e.error) : e
        for load in (() -> include_sources([cfg]; within = dir), () -> load_config_file(cfg; within = dir),
                     () -> include_sources([joinpath(outside, "out.jl")]; within = dir))
            err = try load(); nothing catch e; unwrap(e) end
            @test err isa ArgumentError && occursin("out.jl", err.msg) && occursin("from outside", err.msg)
            @test !@eval(config_file_outside_ran)
        end
        include_sources([cfg])   # (without `within` it runs)
        @test @eval(config_file_outside_ran)
        # the callback is gone afterwards, also after an error
        @test count(c -> parentmodule(typeof(c)) === PDEStudioCore, Base.include_callbacks) == 0
        # `within` as a list of files: only those run; a file added to the folder later is refused like one outside
        cfg = write_config(dir; extra_line = "isfile(joinpath(@__DIR__, \"added.jl\")) && include(\"added.jl\")")
        listed = [cfg, joinpath(dir, "lib", "helper.jl"), joinpath(dir, "lib", "deep", "inner.jl")]
        @test include_sources([cfg]; within = listed) == listed
        write(joinpath(dir, "added.jl"), "global config_file_added_ran = true\n")
        @eval global config_file_added_ran = false
        err = try include_sources([cfg]; within = listed); nothing catch e; unwrap(e) end
        @test err isa ArgumentError && occursin("added.jl", err.msg) && !@eval(config_file_added_ran)
        @test include_sources([cfg]; within = dir)[end] == joinpath(dir, "added.jl")   # (the folder allows it)
        rm(joinpath(dir, "added.jl"))
    end

    @testset "include_sources: files of a package's folder that aren't its source code are seen" begin
        # a package whose folder holds a configuration besides its code (a development checkout): with the package as
        # the target module, the configuration's includes are recorded and checked; the package's own code isn't
        root = mktempdir()
        pkg = joinpath(root, "ConfigFilePkg")
        mkpath(joinpath(pkg, "src")); mkpath(joinpath(pkg, "configs"))
        write(joinpath(pkg, "Project.toml"), "name = \"ConfigFilePkg\"\nuuid = \"5d7a9e4e-6a1c-4c1e-9e1a-0c0ffee00001\"\n")
        write(joinpath(pkg, "src", "ConfigFilePkg.jl"), "__precompile__(false)\nmodule ConfigFilePkg\ninclude(\"code.jl\")\nend\n")
        write(joinpath(pkg, "src", "code.jl"), "pkg_code() = 1\n")
        write(joinpath(pkg, "configs", "helper.jl"), "pkg_helper() = 2\n")
        write(joinpath(pkg, "configs", "cfg.jl"), "include(\"helper.jl\")\n" * body * "\n")
        pushfirst!(LOAD_PATH, root)
        try
            @eval using ConfigFilePkg
            m = @eval ConfigFilePkg
            # (the names the configuration file needs; the package has no dependencies to `using` them from)
            for name in (:SimulationConfig, :create_param_dict, :create_method_dict)
                Core.eval(m, :(const $name = $(getglobal(PDEStudioCore, name))))
            end
            @test PDEStudioCore._package_file(m, joinpath(pkg, "src", "code.jl"))
            # (a file of its folder that it includes into itself is the package's, unless the package is the target module)
            @test PDEStudioCore._package_file(m, joinpath(pkg, "configs", "helper.jl"))
            old_target = get_target_module()
            set_target_module!(m)
            @test !PDEStudioCore._package_file(m, joinpath(pkg, "configs", "helper.jl"))
            included = String[]
            load_config_file(joinpath(pkg, "configs", "cfg.jl"); mod = m, included = included)
            @test included == [joinpath(pkg, "configs", "cfg.jl"), joinpath(pkg, "configs", "helper.jl")]
            # (an include of another file of the package's folder is refused from a bundle there, too)
            err = try include_sources([joinpath(pkg, "configs", "cfg.jl")]; mod = m, within = [joinpath(pkg, "configs", "cfg.jl")]); nothing catch e; e end
            err isa LoadError && (err = err.error)
            @test err isa ArgumentError && occursin("helper.jl", err.msg)
            set_target_module!(old_target)
        finally
            popfirst!(LOAD_PATH)
        end
    end

    @testset "include_sources: a stat preset that a source loads is the package's, not the configuration's" begin
        dir = mktempdir()
        write(joinpath(dir, "with_preset.jl"), "set_stat_preset!(\"hyperbolic\")\n" * body * "\n")
        included = String[]
        load_config_file(joinpath(dir, "with_preset.jl"); included = included)
        @test included == [joinpath(dir, "with_preset.jl")]                       # (the preset file isn't recorded)
        # ... nor refused from a bundle
        names = bundle_sources([joinpath(dir, "with_preset.jl")], joinpath(dir, "bundle"); extra = included)
        @test names.extra == String[]
        @test include_sources(joinpath.(dir, "bundle", names.sources); within = joinpath.(dir, "bundle", names.sources)) ==
              joinpath.(dir, "bundle", names.sources)
    end

    @testset "bundle_sources: a copy that runs on its own" begin
        dir, out = mktempdir(), mktempdir()
        cfg = write_config(dir)
        included = String[]
        config = load_config_file(cfg; included = included)
        bundle = joinpath(out, "exp_sources")
        names = bundle_sources(config.sources, bundle; extra = included)
        @test names.sources == ["solvers.jl", "cfg.jl"]                      # in the order of the sources
        @test names.extra == ["lib/helper.jl", "lib/deep/inner.jl"]          # (what they include, not the sources again)
        @test all(isfile, joinpath.(bundle, [names.sources; names.extra]))
        # without the originals the bundle runs, and only its own files
        rm(dir; recursive = true)
        sources = joinpath.(bundle, names.sources)
        files = include_sources(sources; within = bundle)
        @test Set(files) == Set(joinpath.(bundle, [names.sources; names.extra]))
        copied = load_config_file(last(sources); within = bundle)
        @test copied.shared[:N] == 4 && copied.sources == sources
        # bundling a bundle again keeps the layout; files in place are left alone, other files in the folder too
        write(joinpath(bundle, "notes.txt"), "kept")
        again = bundle_sources(sources, bundle; extra = files)
        @test again.sources == names.sources && Set(again.extra) == Set(names.extra) && isfile(joinpath(bundle, "notes.txt"))
        out2 = joinpath(mktempdir(), "other_sources")
        @test bundle_sources(sources, out2; extra = files).sources == names.sources
        @test read(joinpath(out2, "lib", "helper.jl")) == read(joinpath(bundle, "lib", "helper.jl"))
        # sources in different folders keep their paths relative to the folder they share
        a, b = mktempdir(), mktempdir()
        write(joinpath(a, "x.jl"), "1\n"); write(joinpath(b, "y.jl"), "2\n")
        far = bundle_sources([joinpath(a, "x.jl"), joinpath(b, "y.jl")], joinpath(out, "far"))
        @test all(isfile, joinpath.(out, "far", far.sources)) && basename.(far.sources) == ["x.jl", "y.jl"]
        @test !any(startswith(".."), far.sources) && !any(isabspath, far.sources)
        # errors: a missing file, a file listed twice; no sources, nothing to do
        @test_throws ArgumentError bundle_sources([joinpath(a, "x.jl"), joinpath(a, "gone.jl")], joinpath(out, "e1"))
        @test_throws ArgumentError bundle_sources([joinpath(a, "x.jl")], joinpath(out, "e2"); extra = [joinpath(a, "gone.jl")])
        @test_throws ArgumentError bundle_sources([joinpath(a, "x.jl"), joinpath(a, "x.jl")], joinpath(out, "e3"))
        @test bundle_sources(String[], joinpath(out, "none")) == (sources = String[], extra = String[])
        @test !isdir(joinpath(out, "none"))
    end

    @testset "bundle_digest: what identifies a bundle" begin
        dir, out = mktempdir(), mktempdir()
        cfg = write_config(dir)
        included = String[]
        config = load_config_file(cfg; included = included)
        digest = bundle_digest(config.sources; extra = included)
        @test length(digest) == 64 && all(c -> c in "0123456789abcdef", digest)
        # the same for the copy in a bundle (wherever it is), and for the extra files in another order
        names = bundle_sources(config.sources, joinpath(out, "b1"); extra = included)
        copy_digest(b) = bundle_digest(joinpath.(b, names.sources); extra = joinpath.(b, names.extra))
        @test copy_digest(joinpath(out, "b1")) == digest
        @test bundle_digest(config.sources; extra = reverse(included)) == digest
        mv(joinpath(out, "b1"), joinpath(out, "moved"))
        @test copy_digest(joinpath(out, "moved")) == digest
        # another content, another relative path, a file more or less, or another order of the sources: another digest
        b = joinpath(out, "moved")
        original = read(joinpath(b, "lib", "helper.jl"), String)
        write(joinpath(b, "lib", "helper.jl"), original * "# edited\n")
        @test copy_digest(b) != digest
        write(joinpath(b, "lib", "helper.jl"), original)
        @test copy_digest(b) == digest
        @test bundle_digest(joinpath.(b, names.sources); extra = joinpath.(b, names.extra[1:1])) != digest
        @test bundle_digest(reverse(joinpath.(b, names.sources)); extra = joinpath.(b, names.extra)) != digest
        mkpath(joinpath(b, "other")); mv(joinpath(b, "lib", "helper.jl"), joinpath(b, "other", "helper.jl"))
        @test bundle_digest(joinpath.(b, names.sources); extra = [joinpath(b, "other", "helper.jl"), joinpath(b, "lib", "deep", "inner.jl")]) != digest
        @test_throws ArgumentError bundle_digest([joinpath(b, "gone.jl")])
        @test bundle_digest(String[]) == bundle_digest(String[]; extra = String[]) != digest
        # a label belongs to the identity (the same files, another label: another digest; no label: as before)
        @test bundle_digest(config.sources; extra = included, label = "") == digest
        @test bundle_digest(config.sources; extra = included, label = "builds=file") != digest
        @test bundle_digest(config.sources; extra = included, label = "builds=file") != bundle_digest(config.sources; extra = included, label = "builds=nothing")
    end

    @testset "load_config_function: the configuration a named function builds" begin
        @eval config_file_builder() = $(Meta.parse(body))
        @test load_config_function(:config_file_builder).shared[:N] == 12
        @test load_config_function("config_file_builder").shared[:N] == 12
        @test load_config_function(:test_advection_1d) isa SimulationConfig          # (one of PDEStudioCore's examples)
        @eval config_file_builder_args(N = 12) = $(Meta.parse(body))
        err = try load_config_function(:config_file_builder_args); nothing catch e; e end
        @test err isa ArgumentError && occursin("takes arguments", err.msg)
        # names the target module doesn't define itself (imported ones, too) don't resolve
        for name in (:no_such_config_function, :delete_sim_data, :println)
            err = try load_config_function(name); nothing catch e; e end
            @test err isa ArgumentError && occursin("isn't a function that the target module", err.msg)
        end
    end
end
