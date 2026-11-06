# ARGS: data dir, "save" or "find". Saves a dataset with `:op => :~` (run at a1f8627), or looks it up (at 356e683).
using PDEStudioCore, StaticArrays, Test
include(joinpath(dirname(pathof(PDEStudioCore)), "..", "test", "solvers.jl"))
set_save_path!(ARGS[1])
P = create_param_dict(:N => 20, :scheme => "upwind", :cfl => 0.5, :op => :~)
if ARGS[2] == "save"
    save_sim_data(advection_solver_1d(P); overwrite = true, verbose = false)
    println("saved; stored :op = ", repr(get_clean_params(P)[:op]))
else
    println("normalised :op now = ", repr(get_clean_params(P)[:op]))
    println("does_sim_data_exist (hash): ", does_sim_data_exist(P))
    println("find_sim_data(:op => :~): ", length(find_sim_data(Dict(:op => :~); verbose = false)), " file(s)")
    println("find_sim_data(:N => 20): ", length(find_sim_data(Dict(:N => 20); verbose = false)), " file(s)")
end
