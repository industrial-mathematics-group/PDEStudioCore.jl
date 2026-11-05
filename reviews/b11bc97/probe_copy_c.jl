using PDEStudioCore
set_save_path!(ARGS[1])
struct UserNote; a::Int; end
println("note in a session that defines UserNote: ", typeof(load_sim_data(PDEStudioCore._data_files()[1]; key = "note")))
