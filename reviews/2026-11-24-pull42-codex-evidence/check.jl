using PDEStudioCore, StaticArrays, Logging, JLD2

review_solver(p) = create_sim_data([0.0, 1.0], [10.0, 10.0], p)
function review_offset(d)
    d.u .+= Ref(SVector(1.0))
    return true
end

function repeated_postprocess()
    mktempdir() do dir
        set_save_path!(dir)
        p = create_param_dict(:sim_func_name => :review_solver, :obsolete => 0)
        q = create_param_dict(:sim_func_name => :review_solver)
        config(params) = SimulationConfig(params; postprocess=:review_offset)
        run_all_simulations(config(p))
        source = get_file_name(p)
        imports = import_sim_data(source; remove_keys=[:obsolete])
        before = load_sim_data(q).u[1][1]
        s = run_all_simulations(config(q))
        println("removed unused key: imports=", length(imports), " before=", before,
                " after=", load_sim_data(q).u[1][1], " source=", load_sim_data(p).u[1][1],
                " cached solvers=", length(s.cached), " post=", s.postprocessing)
    end
end

function review_reference(p)
    offset = pop!(p, :offset)
    return _ -> offset
end

function reference_mutation()
    mktempdir() do dir
        set_save_path!(dir)
        p = create_param_dict(:sim_func_name => :review_solver, :offset => 5)
        other = create_param_dict(:sim_func_name => :review_solver)
        save_sim_data(create_sim_data([0.0, 1.0], [80.0, 80.0], other))
        set_stat_preset!("hyperbolic")
        config = SimulationConfig(p; reference=:review_reference, postprocess=:review_offset)
        result = run_all_simulations(config; calculate_stats=true)
        println("reference consumed task key: requested field=", load_sim_data(p).u[1][1],
                " unrelated field=", load_sim_data(other).u[1][1],
                " offset in summary=", haskey(only(result.tasks), :offset),
                " post=", result.postprocessing)
    end
end

function review_diagnostic(p)
    data = review_solver(p)
    add_stat!(data, :iterations, 23, Symbol[])
    return data
end

function solver_statistic()
    mktempdir() do dir
        set_save_path!(dir)
        set_stat_preset!("hyperbolic")
        set_stat_registry!(Dict(:mass => :time))
        p = create_param_dict(:sim_func_name => :review_diagnostic, :obsolete => 0)
        q = create_param_dict(:sim_func_name => :review_diagnostic)
        run_all_simulations(SimulationConfig(p); calculate_stats=true)
        import_sim_data(get_file_name(p); remove_keys=[:obsolete])
        s = run_all_simulations(SimulationConfig(q); calculate_stats=true)
        d = load_sim_data(q)
        println("solver-attached diagnostic: source=", load_sim_data(p).stats[:iterations][1],
                " imported has iterations=", haskey(d.stats, :iterations), " has mass=", haskey(d.stats, :mass),
                " solvers ran=", length(s.ran))
    end
end

function rational_grid()
    T = Rational{Int}
    domain = DomainInfo{1,T}((:x,), (0//1,), (1//1,), (1//3,), nothing)
    d = generate_reference_simdata(_ -> SVector(1//1), ParamDict(), domain, (4,), :eulerian)
    println("rational reference: actual first interval=", d.axes[1][2]-d.axes[1][1],
            " stored spacing=", only(d.domain.spacing))
end

function user_entries()
    mktempdir() do dir
        set_save_path!(dir)
        p = create_param_dict(:case => 1)
        d = review_solver(p)
        path = save_sim_data(d)
        jldopen(path, "a+") do f
            dataset = JLD2.create_dataset(f, "calibration")
            JLD2.add_attribute(dataset, "units", "kelvin")
            JLD2.write_dataset(dataset, 47)
            JLD2.Group(f, "pending_measurements")
        end
        inspect() = jldopen(path, "r") do f
            attrs = JLD2.attributes(JLD2.get_dataset(f, "calibration"))
            (value=f["calibration"], units=get(attrs, "units", missing), group=haskey(f, "pending_measurements"))
        end
        before = inspect()
        d.metadata[:note] = "completed"
        save_sim_data(d; overwrite=true)
        println("ordinary rewrite: before=", before, " after=", inspect())
    end
end

with_logger(NullLogger()) do
    repeated_postprocess()
    rational_grid()
    user_entries()
    reference_mutation()
    solver_statistic()
end
