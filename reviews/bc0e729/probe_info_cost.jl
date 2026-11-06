# Cost of get_sim_data_info: new files vs files without "dim_keys"/"time_dim" (fallback loads "raw" on every call);
# error for a file without "native"/"shape".
using PDEStudioCore, StaticArrays
using PDEStudioCore: JLD2
set_save_path!(mktempdir())
p = create_param_dict(:case => "big")
nx, nt = 2000, 500   # 10^6 SVector{1, Float64} = 8 MB
save_sim_data(create_sim_data(collect(range(0, 1; length = nx)), rand(nx, nt), collect(range(0, 1; length = nt)), p); verbose = false)
path = get_file_name(p)
get_sim_data_info(p)
println("new file: ", round(@elapsed(get_sim_data_info(p)) * 1e3; sigdigits = 3), " ms, ",
        round(@allocated(get_sim_data_info(p)) / 2^20; sigdigits = 3), " MiB")
function strip_entries!(path, drop)
    entries = JLD2.jldopen(f -> Dict(k => f[k] for k in keys(f) if !(k in drop)), path, "r")
    rm(path)
    JLD2.jldopen(path, "w") do f
        for (k, v) in entries; f[k] = v; end
    end
end
strip_entries!(path, ("dim_keys", "time_dim"))
for i in 1:3
    t = @elapsed(get_sim_data_info(p)); a = @allocated(get_sim_data_info(p))
    println("old file, call $i: ", round(t * 1e3; sigdigits = 3), " ms, ", round(a / 2^20; sigdigits = 3), " MiB; ",
            "dim_keys written back: ", JLD2.jldopen(f -> haskey(f, "dim_keys"), path, "r"))
end
println("info params given as a plain Dict with unnormalised values: ",
        get_sim_data_info(Dict(:case => "big")).n_steps)
strip_entries!(path, ("native", "shape"))
r = try get_sim_data_info(p); "no error" catch e; sprint(showerror, e) end
println("file without native/shape: ", r)
