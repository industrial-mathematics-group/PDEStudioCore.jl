using PDEStudioCore, StaticArrays
set_save_path!(ARGS[1])
x = collect(range(0.0, 1.0, length = 50))
for (i, big) in ((1, true), (2, false))
    p = create_param_dict(:bigentry => i)
    d = create_sim_data(x, [SVector(1.0) for i in 1:50, j in 1:4], [0.0, 1.0, 2.0, 3.0], p)
    save_sim_data(d; metadata = big ? Dict("reference_field" => rand(10_000_000)) : Dict("note" => 1))
end
