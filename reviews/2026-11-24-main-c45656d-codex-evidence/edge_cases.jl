using PDEStudioCore, JLD2, Logging, StaticArrays

module ParameterTypes
struct Matrix end
end

function matrix_tag_solver(p)
    value = p[:tag] === Val{ParameterTypes.Matrix}() ? 20.0 : 10.0
    return create_sim_data([0.0, 1.0], fill(value, 2), p)
end

function check_type_tag_collision()
    mktempdir() do root
        set_save_path!(root)
        for (label, tag) in (("Base.Matrix", Val{Matrix}()), ("ParameterTypes.Matrix", Val{ParameterTypes.Matrix}()))
            p = create_param_dict(:sim_func_name => :matrix_tag_solver, :tag => tag)
            s = run_all_simulations(SimulationConfig(p))
            println(label, ": text=", repr(val2str(tag)), " stored_tag=", repr(get_clean_params(p)[:tag]),
                    " hash=", calculate_hash(p), " ran=", length(s.ran), " cached=", length(s.cached),
                    " field=", first(first(load_sim_data(p).u)))
        end
    end
end

unit_field_solver(p) = create_sim_data([0.0, 1.0], [1.0, 1.0], p)

function check_reference_registry()
    mktempdir() do root
        set_save_path!(root)
        set_stat_preset!("hyperbolic")
        set_stat_registry!(Dict(:l1error => :time))
        reference_file = joinpath(root, "reference.jl")
        function set_reference(value)
            write(reference_file, "registry_reference(p) = _ -> $value\n")
            Base.include(Main, reference_file)
        end
        p = create_param_dict(:sim_func_name => :unit_field_solver)
        cfg = SimulationConfig(p; reference = :registry_reference)
        run(; kwargs...) = Base.invokelatest(run_all_simulations, cfg; calculate_stats = true, kwargs...)
        function print_stats(label, summary)
            d = load_sim_data(p)
            l1 = haskey(d.stats, :l1error) ? only(d.stats[:l1error]) : missing
            l2 = haskey(d.stats, :l2error) ? only(d.stats[:l2error]) : missing
            path = get_file_name(p)
            record = jldopen(file -> file["evaluated_reference"], path, "r")
            println(label, ": stats=", only(keys(summary.stats)), " L1=", l1, " L2=", l2, " record=", record)
        end

        set_reference(2.0)
        print_stats("A with L1", run())
        set_reference(4.0)
        delete_stat!(:l1error)
        register_stat!(:l2error, :time)
        file = get_file_name(p)
        before_dry_run = read(file)
        log = IOBuffer()
        dry = with_logger(SimpleLogger(log, Logging.Warn)) do
            run(; dry_run = true)
        end
        dry_log = String(take!(log))
        println("B dry run: stats=", only(keys(dry.stats)), " file_unchanged=", read(file) == before_dry_run,
                " claims_completed_refresh=", occursin("were evaluated again", dry_log))
        print_stats("B with L2 active", run())
        register_stat!(:l1error, :time)
        print_stats("B with L1 restored", run())
        println("Expected against B: L1=6.0 L2=", sqrt(18.0))
    end
end

module ∇Tags
struct GradientTag end
end

function check_mathematical_identifier()
    p = create_param_dict(:tag => ∇Tags.GradientTag)
    before = (val2str(p[:tag]), calculate_hash(p))
    Base.eval(Main, :(using .∇Tags: GradientTag))
    after = (Base.invokelatest(val2str, p[:tag]), Base.invokelatest(calculate_hash, p))
    println("Mathematical module identifier: before=", before, " after=", after)
end

function check_float64_scatter()
    p = create_sim_data([SVector(0.0)], [1.0e300], ParamDict())
    g = convert_to_eulerian(p, (1,))
    println("Float64 one-particle scatter: input=", only(only(only(p.u))), " output=", only(only(g.u)))
end

with_logger(NullLogger()) do
    check_type_tag_collision()
    check_reference_registry()
    check_mathematical_identifier()
    check_float64_scatter()
end
