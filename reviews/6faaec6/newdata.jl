using PDEStudioCore, StaticArrays
set_save_path!(mktempdir())
p = create_param_dict(:nd => 1)
mk(v) = create_sim_data(collect(0.0:0.5:1.0), [SVector(v) for i in 1:3, j in 1:2], [0.0, 1.0], p)
save_sim_data(mk(1.0); verbose = false, metadata = Dict(:note => "user note", :iterations => 3))
save_sim_data(mk(2.0); overwrite = true, verbose = false)    # new data, own metadata empty
println(sort(collect(keys(load_sim_data(p).metadata))))
