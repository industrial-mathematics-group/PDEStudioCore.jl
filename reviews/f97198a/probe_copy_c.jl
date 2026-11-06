using PDEStudioCore
set_save_path!(ARGS[1])
struct UserNote; a::Int; end
n = load_sim_data(only(PDEStudioCore._data_files()); key = "note")
println("C: note is ", typeof(n), " ", n isa UserNote ? "OK" : "DEGRADED")
