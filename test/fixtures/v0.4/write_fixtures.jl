# Writes the files in data/ with PDEStudioCore 0.4.4 (main_dev at 2818d7e): data files of the format before the
# metadata field, read by test_data.jl ("files of 0.4"). Run with that version: julia write_fixtures.jl <save path>
using PDEStudioCore, StaticArrays
set_save_path!(ARGS[1])
PDEStudioCore.set_target_module!(@__MODULE__)
p = create_param_dict(:n => 5, :kind => "eul")
x = collect(range(0.0, 1.0, length = 5))
d = create_sim_data(x, fill(SVector(1.0, 2.0), 5, 3), [0.0, 0.5, 1.0], p)
calculate_all_stats!(d; save = false)
save_sim_data(d; metadata = Dict("note" => "hello", "iterations" => 3))
q = create_param_dict(:n => 4, :kind => "lag")
t = [0.0, 1.0]
l = create_sim_data([[SVector(i + ti) for i in 1.0:4.0] for ti in t], [[SVector(1.0) for _ in 1:4] for _ in t], t, q)
save_sim_data(l)
enable_cache!(true); load_sim_data(p, :lagrangian)   # a cached conversion in the file
println("written ", readdir(joinpath(ARGS[1], "data")))
