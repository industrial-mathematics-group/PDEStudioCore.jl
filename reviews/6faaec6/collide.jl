using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
set_save_path!(mktempdir())
p = create_param_dict(:collide => 1)
d = create_sim_data(collect(0.0:0.5:1.0), [SVector(1.0) for i in 1:3, j in 1:2], [0.0, 1.0], p; metadata = Dict(:note => "metadata note"))
save_sim_data(d; verbose = false)
path = get_file_name(p)
JLD2.jldopen(path, "a+") do f; f["note"] = "my own entry"; f["other"] = "kept?"; end
e = load_sim_data(p); add_stat!(e, :extra, 1.0, Symbol[])
save_sim_data(e; overwrite = true, verbose = false)
println(JLD2.jldopen(f -> (haskey(f, "note"), haskey(f, "other")), get_file_name(p), "r"))
