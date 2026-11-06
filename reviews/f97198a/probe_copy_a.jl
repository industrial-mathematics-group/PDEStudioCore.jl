using PDEStudioCore, StaticArrays
set_save_path!(ARGS[1])
struct UserNote; a::Int; end
x = collect(range(0.0, 1.0, length = 5))
d = create_sim_data(x, fill(SVector(1.0), 5, 2), [0.0, 1.0], create_param_dict(:case => "copy"))
mode = ARGS[2]
if mode == "withstats"
    set_stat_preset!("hyperbolic")
    calculate_all_stats!(d; save = false)
end
save_sim_data(d; metadata = Dict("note" => UserNote(3)))
println("A saved (", mode, ")")
