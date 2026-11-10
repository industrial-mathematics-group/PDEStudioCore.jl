using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
tmp = mktempdir(); cp(ARGS[1], joinpath(tmp, "s")); set_save_path!(joinpath(tmp, "s"))
PDEStudioCore.set_target_module!(@__MODULE__)
noop(d) = nothing
for i in (1, 2)
    p = create_param_dict(:bigentry => i)
    load_sim_data(p); sim_data_table()
    st = @timed load_sim_data(p); println(i, " load_sim_data ", round(st.time, digits = 3), " s, ", round(st.bytes / 2^20, digits = 1), " MiB; metadata keys ", collect(keys(st.value.metadata)))
    path = get_file_name(p); s0 = filesize(path)
    pp = merge(p, Dict(:sim_func_name => :nothing_solver))
    s = run_all_simulations(SimulationConfig(p; postprocess = :noop))
    println(i, " postprocessing ", s.postprocessing, ": file ", round(s0 / 2^20, digits = 1), " -> ", round(filesize(path) / 2^20, digits = 1), " MiB")
end
st = @timed sim_data_table(); println("table ", round(st.time, digits = 3), " s, ", round(st.bytes / 2^20, digits = 1), " MiB")
