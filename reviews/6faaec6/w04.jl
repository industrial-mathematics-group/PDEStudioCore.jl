# Writes 0.4.4 files of many kinds into ARGS[1]
using PDEStudioCore, StaticArrays, JLD2
set_save_path!(ARGS[1])
PDEStudioCore.set_target_module!(@__MODULE__)
enable_cache!(true)
# 1 Eulerian transient M=2 with user metadata + stats + conv caches
p1 = create_param_dict(:case => 1)
x = collect(range(0.0, 1.0, length = 6))
d1 = create_sim_data(x, [SVector(float(i), 2.0j) for i in 1:6, j in 1:3], [0.0, 0.5, 1.0], p1)
calculate_all_stats!(d1)
save_sim_data(d1; overwrite = true, metadata = Dict("note" => "hello", :iterations => 3))
load_sim_data(p1, :lagrangian); load_sim_data(p1, :eulerian, (3, 2))
# 2 static Eulerian 2D Float32, M=5
p2 = create_param_dict(:case => 2)
d2 = create_sim_data((collect(Float32, 0:0.25:1), collect(Float32, 0:0.5:1)), fill(SVector{5, Float32}(1, 2, 3, 4, 5), 5, 3), p2)
save_sim_data(d2)
# 3 Lagrangian static, 4 Lagrangian transient Float32
p3 = create_param_dict(:case => 3)
save_sim_data(create_sim_data([SVector(0.1i, 0.2i) for i in 1:4], [SVector(1.0) for _ in 1:4], p3))
p4 = create_param_dict(:case => 4)
t = Float32[0, 1, 2]
l4 = create_sim_data([[SVector{1, Float32}(i + ti) for i in 1:4] for ti in t], [[SVector{3, Float32}(1, 2, 3) for _ in 1:4] for _ in t], t, p4)
calculate_all_stats!(l4); save_sim_data(l4)
load_sim_data(p4, :eulerian, (4, 3))
# 5 user entries with names this version uses + a group
p5 = create_param_dict(:case => 5)
d5 = create_sim_data(x, [SVector(1.0) for i in 1:6, j in 1:2], [0.0, 1.0], p5)
save_sim_data(d5; metadata = Dict("format_version" => 7, "provenance" => "mine", "postprocessed" => [1, 2]))
jldopen(get_file_name(p5), "a+") do f; f["grp/a"] = 1; f["grp/b"] = "two"; end
# 6 user entry called "metadata" (not reserved in 0.4)
p6 = create_param_dict(:case => 6)
save_sim_data(create_sim_data(x, [SVector(1.0) for i in 1:6, j in 1:2], [0.0, 1.0], p6); metadata = Dict("metadata" => "my string"))
# 7 version 0: data only
p7 = create_param_dict(:case => 7)
d7 = create_sim_data(x, [SVector(1.0) for i in 1:6, j in 1:2], [0.0, 1.0], p7)
h = calculate_hash(get_clean_params(p7))
jldopen(joinpath(ARGS[1], "data", "20260101-000000_$h.jld2"), "w") do f; f["raw"] = d7; end
# 8 a user entry 0.4 itself refused? (sources written by a pipeline run with sources)
src = joinpath(ARGS[1], "solver8.jl")
write(src, "solver8(p) = create_sim_data(collect(range(0.0, 1.0, length = 4)), [SVector(1.0) for i in 1:4, j in 1:2], [0.0, 1.0], p)\n")
cfg = SimulationConfig(Dict{Symbol,Any}(:case => 8, :sim_func_name => :solver8); sources = [src])
run_all_simulations(cfg; calculate_stats = true)
println("written ", length(readdir(joinpath(ARGS[1], "data"))))
