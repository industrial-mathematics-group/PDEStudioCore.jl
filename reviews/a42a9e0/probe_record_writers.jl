# Which writers keep / replace / omit the record entries
include(joinpath(@__DIR__, "common.jl"))
const CALLS = Ref(0)
cnt_post(d) = (CALLS[] += 1; nothing)
cfg = SimulationConfig(Dict(:sim_func_name => :lin_solver, :n => 4); postprocess = :cnt_post)
p = only(generate_tasks(cfg))
with_logger(NullLogger()) do; run_all_simulations(cfg); end
path = get_file_name(p)
println("pipeline: solver=", get(prov(path), "solver", nothing), " wall_time=", haskey(prov(path), "wall_time"), " record=", rec(path) !== nothing)
# 1. the documented way to persist add_stat! values: save_sim_data(data; overwrite = true) of the SAME data
d = load_sim_data(p)
add_stat!(d, :my_value, 1.0, Symbol[])
save_sim_data(d; overwrite = true, verbose = false)
println("after save_sim_data(same data; overwrite): solver=", get(prov(path), "solver", nothing),
        " wall_time=", haskey(prov(path), "wall_time"), " record=", rec(path))
with_logger(NullLogger()) do; run_all_simulations(cfg); end
println("post-processor calls after that rerun: ", CALLS[], " (was 1)")
# 2. calculate_all_stats! of data not stored yet: writes a new file
q = create_param_dict(:n => 7, :sim_func_name => :lin_solver)
d2 = lin_solver(q)
with_logger(NullLogger()) do; calculate_all_stats!(d2); end
path2 = get_file_name(q)
println("calculate_all_stats! new file: provenance=", prov(path2), " format_version=", JLD2.jldopen(f -> f["format_version"], path2, "r"))
# 3. user metadata with value nothing
q3 = create_param_dict(:n => 9)
save_sim_data(lin_solver(q3); verbose = false, metadata = Dict("note" => nothing, "other" => 1))
println("metadata note=>nothing stored: ", JLD2.jldopen(f -> haskey(f, "note"), get_file_name(q3), "r"))
