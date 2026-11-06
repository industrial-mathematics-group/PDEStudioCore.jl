# Run with the OLD code (6e36904): writes every dataset into ARGS[1]
include(joinpath(@__DIR__, "datasets.jl"))
set_save_path!(ARGS[1])
@assert !isdefined(PDEStudioCore, :get_sim_data_info)
println("PDEStudioCore at ", pathof(PDEStudioCore))
for (name, d) in make_datasets()
    save_sim_data(d; overwrite = true, verbose = false)
end
println("written ", length(readdir(joinpath(ARGS[1], "data"))), " files")
# an old file with user metadata named like the new managed entries
set_save_path!(joinpath(ARGS[1], "meta"))
save_sim_data(create_sim_data(collect(0.0:0.5:1.0), rand(3, 2), [0.0, 1.0], create_param_dict(:case => "usermeta"));
              metadata = Dict("dim_keys" => ["user"], "time_dim" => "user value"), verbose = false)
println("written usermeta")
