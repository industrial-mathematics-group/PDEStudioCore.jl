using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
set_save_path!(mktempdir())
pe = create_param_dict(:big => :E)
de = create_sim_data((collect(range(0.0, 1.0, length = 400)), collect(range(0.0, 1.0, length = 400))),
                     [SVector(rand(), rand(), rand(), rand()) for i in 1:400, j in 1:400, k in 1:10], collect(1.0:10.0), pe)
save_sim_data(de; verbose = false)
pl = create_param_dict(:big => :L)
t = collect(1.0:1000.0)
dl = create_sim_data([[SVector(rand(), rand()) for _ in 1:5000] for _ in t], [[SVector(rand()) for _ in 1:5000] for _ in t], t, pl)
save_sim_data(dl; verbose = false)
de = dl = nothing; GC.gc()
for p in (pe, pl)
    path = get_file_name(p)
    plain() = JLD2.jldopen(f -> f["raw"], path, "r")
    up() = PDEStudioCore._open_data(f -> f["raw"], path)
    full() = load_sim_data(p)
    plain(); up(); full()
    for (n, g) in (("plain", plain), ("typemap", up), ("load_sim_data", full))
        GC.gc()
        st = @timed g()
        println(p[:big], " ", rpad(n, 14), " time ", round(st.time, digits = 3), " s, alloc ", round(st.bytes / 2^20, digits = 1), " MiB")
    end
    println(filesize(path) / 2^20, " MiB file")
end
