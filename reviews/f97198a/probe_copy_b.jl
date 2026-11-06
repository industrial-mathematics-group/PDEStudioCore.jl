using PDEStudioCore, StaticArrays
set_save_path!(ARGS[1])
p = create_param_dict(:case => "copy")
mode = ARGS[2]
f = only(PDEStudioCore._data_files())
s0 = filesize(f)
if mode == "cache"
    enable_cache!(true)
    load_sim_data(p, :eulerian, (9, 2)); load_sim_data(p, :lagrangian)
    println("B cached: ", list_available_conversions(p), " size ", s0, " -> ", filesize(f))
elseif mode == "stats"   # stats pass in a session without UserNote
    set_stat_preset!("hyperbolic")
    d = load_sim_data(p)
    calculate_all_stats!(d)
    println("B stats pass: size ", s0, " -> ", filesize(f), "; stat keys ", sort(collect(keys(load_sim_data(p).stats))))
end
