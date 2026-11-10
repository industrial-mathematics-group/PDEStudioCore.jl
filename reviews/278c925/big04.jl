# F5: a 0.4 file with a large user entry (76 MB), post-processing with a `nothing` return
using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
PDEStudioCore.set_target_module!(@__MODULE__)
tmp = mktempdir(); cp(ARGS[1], joinpath(tmp, "s")); set_save_path!(joinpath(tmp, "s"))
p = create_param_dict(:case => 1); f = get_file_name(p)
JLD2.jldopen(h -> (h["bigref"] = rand(10^7)), f, "a+")
noop(d) = nothing; noop2(d) = nothing
mb(x) = round(x / 2^20, digits = 1)
load_sim_data(p); println("load: ", mb(@allocated load_sim_data(p)), " MiB; file ", mb(filesize(f)), " MiB")
for post in (:noop, :noop2, :noop)
    s = run_all_simulations(SimulationConfig(p; postprocess = post); force_postprocess = post === :noop)
    println(post, " => ", s.postprocessing, "; file ", mb(filesize(f)), " MiB; v", JLD2.jldopen(PDEStudioCore._format_version, f, "r"))
end
println("keys: ", sort(collect(keys(load_sim_data(p).metadata[:postprocessed]))))
