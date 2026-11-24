using PDEStudioCore, StaticArrays, JLD2, Logging

p(k; extras...) = create_param_dict(:sim_func_name => :review_solver, :k => k, extras...)
function review_solver(params)
    d = create_sim_data([0.0, 1.0], fill(Float64(params[:k]), 2), params)
    add_stat!(d, :iterations, 23, Symbol[])
    return d
end
function add_one!(d)
    d.u .+= Ref(SVector(1.0))
    return true
end
review_ref(params) = (pop!(params, :offset, nothing); _ -> 0.0)

function recorded_import()
    set_save_path!(mktempdir())
    set_stat_registry!(Dict(:mass => :time))
    a, b = p(10; obsolete=0), p(10)
    cfg(params) = SimulationConfig(params; postprocess=:add_one!)
    run_all_simulations(cfg(a); calculate_stats=true)
    source = get_file_name(a)
    backup = joinpath(mktempdir(), "run.jld2")
    cp(source, backup)
    result = import_sim_data(backup; remove_keys=[:obsolete])
    s = run_all_simulations(cfg(b); calculate_stats=true)
    d = load_sim_data(b)
    println("unused import key: imports=", length(result), " source bytes preserved=", read(source)==read(backup), " field=", d.u[1][1],
            " diagnostic=", only(d.stats[:iterations]), " mass=", only(d.stats[:mass]), " post=", s.postprocessing)
    println("interactive import keyword: ", try import_sim_data(backup; prompt_keys=[:k]); :accepted catch e; typeof(e) end)
end

function copied_reference()
    set_save_path!(mktempdir())
    set_stat_registry!(Dict(:l1error => :time))
    task, other = p(10; offset=5), p(10)
    save_sim_data(create_sim_data([0.0, 1.0], [80.0, 80.0], other))
    s = run_all_simulations(SimulationConfig(task; reference=:review_ref, postprocess=:add_one!); calculate_stats=true)
    println("mutating reference factory: requested=", load_sim_data(task).u[1][1], " unrelated=", load_sim_data(other).u[1][1],
            " task kept offset=", haskey(only(s.tasks), :offset))
end

function copied_entries()
    set_save_path!(mktempdir())
    data = review_solver(p(10))
    path = save_sim_data(data)
    jldopen(path, "a+") do f
        extra = JLD2.create_dataset(f, "calibration")
        JLD2.add_attribute(extra, "units", "kelvin")
        JLD2.write_dataset(extra, 47)
        JLD2.Group(f, "pending")
    end
    data.metadata[:note] = "metadata edit"
    save_sim_data(data; overwrite=true)
    attrs = jldopen(f -> (f["calibration"], JLD2.load_attributes(f, "calibration")["units"], isempty(keys(f["pending"]))), path)
    println("rewrite user entry: ", attrs)
    jldopen(path, "a+") do f
        JLD2.add_attribute(JLD2.get_dataset(f, "pending"), "units", "kelvin")
    end
    orig = read(path)
    result = try
        save_sim_data(data; overwrite=true)
        "saved"
    catch e
        replace(sprint(showerror, e), basename(path) => "<run>.jld2")
    end
    println("rewrite group with attributes: original preserved=", read(path)==orig, " outcome=", result)
end

function broken_destination()
    set_save_path!(mktempdir())
    path = save_sim_data(review_solver(p(10)))
    backup = joinpath(mktempdir(), "run.jld2")
    cp(path, backup)
    jldopen(path, "a+") do f
        delete!(f, "raw")
    end
    bytes = read(path)
    println("import incomplete destination: imported=", length(import_sim_data(backup)), " destination preserved=", read(path)==bytes)
end

with_logger(NullLogger()) do
    set_stat_preset!("hyperbolic")
    Base.invokelatest(recorded_import)
    Base.invokelatest(copied_reference)
    copied_entries()
    broken_destination()
end
