# data.md: "These names, and the other entries of this table, are reserved: save_sim_data(...; metadata) refuses them"
using PDEStudioCore
set_save_path!(mktempdir())
x = collect(0.0:0.5:1.0)
for k in ("raw", "native", "shape", "dim_keys", "time_dim", "evaluated_stats", "evaluated_with_reference", "sources", "conv_L", "conv_E_3x2")
    p = create_param_dict(:case => "res_" * k)
    r = try save_sim_data(create_sim_data(x, rand(3, 2), [0.0, 1.0], p); metadata = Dict(k => "user"), verbose = false); "ACCEPTED"
        catch e; e isa ArgumentError ? "refused" : string(typeof(e)) end
    println(rpad(k, 28), r)
end
