# provenance on all writers; `nothing` metadata
include(joinpath(@__DIR__, "common.jl"))
q(f) = with_logger(NullLogger()) do; f(); end
p = create_param_dict(:sim_func_name => :lin_solver, :n => 4, :a => 1)
q(() -> run_all_simulations(SimulationConfig(p)))
path = get_file_name(p); pv = prov(path)
# conversion cache
enable_cache!(true)
q(() -> load_sim_data(p, :lagrangian))
println("conversion cache: keys=", list_available_conversions(p), " provenance kept=", prov(get_file_name(p)) == pv)
enable_cache!(false)
# rehash to a new name (filter out :a)
newp = q(() -> rehash_sim_data(get_file_name(p); remove_keys = [:a]))
p2 = create_param_dict(:sim_func_name => :lin_solver, :n => 4)
println("rehash to new name: ", basename(get_file_name(p2)) != basename(path), " provenance kept=", prov(get_file_name(p2)) == pv)
# upgrade of a version-0 file (only raw)
r = create_param_dict(:sim_func_name => :lin_solver, :n => 7)
sim = lin_solver(copy(r)); f0 = q(() -> save_sim_data(sim)); rm(f0); JLD2.jldopen(f -> (f["raw"] = sim), f0, "w")
q(() -> upgrade_sim_data(f0))
println("upgraded version-0 file: provenance=", prov(f0))
# `nothing` user metadata via run_smart_simulation and save_sim_data
m = create_param_dict(:sim_func_name => :lin_solver, :n => 9)
q(() -> run_smart_simulation(lin_solver, m; metadata = Dict("note" => nothing)))
println("run_smart_simulation note=>nothing stored: ", JLD2.jldopen(f -> haskey(f, "note") ? repr(f["note"]) : "absent", get_file_name(m), "r"))
