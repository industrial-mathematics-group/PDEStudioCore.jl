using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)

action, root = ARGS
set_save_path!(root)
file_format(path) = PDEStudioCore.JLD2.jldopen(PDEStudioCore._format_version, path, "r")
function ownership_solver(p)
    d = create_sim_data([0.0, 1.0], [1.0, 1.0], p)
    add_stat!(d, :calibration, 47.0, Symbol[])
    return d
end
function ownership_post(d)
    scratch = create_sim_data([0.0, 1.0], [0.0, 0.0], ParamDict())
    add_stat!(scratch, :calibration, 99.0, Symbol[])
    add_stat!(d, :quality, 2.0, Symbol[])
    return true
end
PDEStudioCore.calc_stat(::Val{:maintenance}, coords, u, domain) = first(u)
p = create_param_dict(:sim_func_name => :ownership_solver)
c = SimulationConfig(p; postprocess = :ownership_post)

function attempt(f, description)
    try
        f()
        println(description, ": returned")
    catch err
        println(description, ": ", sprint(showerror, err))
    end
end

if action == "old"
    set_stat_preset!("hyperbolic")
    set_stat_registry!(Dict(:l2norm => Symbol[]))
    run_all_simulations(c; calculate_stats = true)
    d = load_sim_data(p)
    println("Prepared a 0.9 file: ", sort!(collect(keys(d.stats))))
elseif action == "misown"
    r = run_all_simulations(c; force_postprocess = true)
    d = load_sim_data(p)
    println("Prepared a #70 file: ", r.postprocessing, " owner keys=", d.metadata[:postprocessed][:ownership_post][:keys])
elseif action == "check"
    path = get_file_name(p)
    original = read(path)
    d = load_sim_data(p)
    println("Raw format=", file_format(path), " calibration=", first(d.stats[:calibration]))
    set_stat_registry!(Dict(:maintenance => Symbol[]))
    r = run_all_simulations(c; calculate_stats = true, force_postprocess = true)
    println("Normal passes: stats=", r.stats, " post=", r.postprocessing, " unchanged=", read(path) == original)
    attempt(() -> save_sim_data(d; overwrite = true, verbose = false), "In-place save")
    println("Original unchanged after save attempt=", read(path) == original)

    mktempdir() do destination
        set_save_path!(destination)
        println("Imported legacy files=", length(import_sim_data(path)))
    end

    set_save_path!(root)
    if read(path) == original
        enable_cache!(true)
        converted = load_sim_data(p, :eulerian, (3,))
        println("Converted length=", length(converted.u), " original bytes unchanged=", read(path) == original,
                " format=", file_format(path), " cached keys=", list_available_conversions(p))
        enable_cache!(false)
    end

    r = run_all_simulations(c; force_overwrite = true, calculate_stats = true)
    println("Recompute: format=", file_format(path), " stats=", r.stats, " post=", r.postprocessing,
            " calibration=", first(load_sim_data(p).stats[:calibration]))
elseif action == "edited"
    path = get_file_name(p)
    d = load_sim_data(p)
    println("Before edit: format=", file_format(path), " l2=", first(d.stats[:l2norm]))
    d.u = [PDEStudioCore.StaticArrays.SVector(2.0), PDEStudioCore.StaticArrays.SVector(2.0)]
    attempt(() -> save_sim_data(d; overwrite = true, verbose = false), "Save of edited legacy dataset")
    d = load_sim_data(p)
    println("After edit: format=", file_format(path), " u=", collect(d.u),
            " stored l2=", get(d.stats, :l2norm, "omitted"))
    set_stat_preset!("hyperbolic")
    set_stat_registry!(Dict(:l2norm => Symbol[]))
    r = run_all_simulations(c; calculate_stats = true, post_process = false)
    println("Refresh after edit: ", r.stats, " errors=", last.(r.stats_failed),
            " stored l2=", get(load_sim_data(p).stats, :l2norm, "omitted"), " expected=", sqrt(8.0))
elseif action == "future"
    run_all_simulations(SimulationConfig(p))
    path = get_file_name(p)
    PDEStudioCore._set_key!(path, "format_version", 5)
    original = read(path)
    mktempdir() do destination
        set_save_path!(destination)
        println("Imports of simulated format 5=", length(import_sim_data(path)))
    end
    set_save_path!(root)
    set_stat_registry!(Dict(:maintenance => Symbol[]))
    println("Simulated future file, initial format=", file_format(path))
    r = run_all_simulations(SimulationConfig(p); calculate_stats = true)
    println("Statistics pass=", r.stats, " now format=", file_format(path),
            " file unchanged=", read(path) == original)
elseif action == "direct"
    path = get_file_name(p)
    before = read(path)
    d = load_sim_data(p)
    println("Before direct calculation: calibration layer=", stat_layer(d, :calibration))
    set_stat_registry!(Dict(:maintenance => Symbol[]))
    attempt(() -> calculate_all_stats!(d; save = false), "In-memory statistics call")
    println("After in-memory call: has calibration=", haskey(d.stats, :calibration),
            " original file bytes unchanged=", read(path) == before)
end
