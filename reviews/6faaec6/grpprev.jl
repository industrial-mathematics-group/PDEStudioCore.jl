using PDEStudioCore, StaticArrays
tmp = mktempdir(); cp(ARGS[1], joinpath(tmp, "s")); set_save_path!(joinpath(tmp, "s"))
h5 = calculate_hash(get_clean_params(create_param_dict(:case => 5)))[1:10]
e = load_sim_data(h5)
println(sort(collect(keys(e))))
v = haskey(e, "grp/a") ? e["grp/a"] : try e["grp"]["a"] catch err; sprint(showerror, err) end
println("grp a: ", v)
