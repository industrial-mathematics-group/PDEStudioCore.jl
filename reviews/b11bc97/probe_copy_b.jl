using PDEStudioCore, StaticArrays
set_save_path!(ARGS[1])
p = create_param_dict(:case => "copy")
enable_cache!(true)
try
    e = load_sim_data(p, :eulerian, (9, 2))
    println("conversion returned ", typeof(e), "; cached: ", list_available_conversions(p))
    println("note now: ", typeof(load_sim_data(PDEStudioCore._data_files()[1]; key = "note")))
catch err
    println("load_sim_data threw: ", typeof(err), ": ", first(sprint(showerror, err), 300))
end
