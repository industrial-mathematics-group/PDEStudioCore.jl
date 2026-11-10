# a v3 file a 0.4 writer rewrote (top-level "sources" from 0.4 next to the stale "metadata"), rewritten by this version
using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
tmp = mktempdir(); cp(ARGS[1], joinpath(tmp, "s")); set_save_path!(joinpath(tmp, "s"))
f = first(filter(endswith(".jld2"), readdir(joinpath(get_save_path(), "data"); join = true)))
println("before: ", JLD2.jldopen(h -> (h["sources"], sort(collect(keys(h["metadata"])))), f, "r"))
d = load_sim_data(basename(f); key = "raw")
add_stat!(d, :extra, 1.0, Symbol[])
save_sim_data(d; overwrite = true, verbose = false)
println("after rewrite: top-level sources kept: ", JLD2.jldopen(h -> haskey(h, "sources"), f, "r"), "; metadata[:sources]: ", get(load_sim_data(basename(f); key = "raw").metadata, :sources, :none))
