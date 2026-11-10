# Reads the 0.4 files of w04.jl with the new code
using PDEStudioCore, StaticArrays, Test; const JLD2 = PDEStudioCore.JLD2; using .JLD2: jldopen
tmp = mktempdir(); cp(ARGS[1], joinpath(tmp, "s"); force = true)
set_save_path!(joinpath(tmp, "s"))
PDEStudioCore.set_target_module!(@__MODULE__)
P(i) = create_param_dict(:case => i)
P8 = Dict{Symbol,Any}(:case => 8, :sim_func_name => :solver8)
function try_(label, f)
    try
        r = f(); println("OK   $label => ", r)
    catch e
        println("FAIL $label => ", sprint(showerror, e)[1:min(end, 300)])
    end
end
for i in 1:7
    try_("load $i", () -> (d = load_sim_data(P(i)); (typeof(d), d.metadata)))
end
try_("load 8", () -> (d = load_sim_data(P8); (typeof(d), keys(d.metadata))))
try_("conv_L 1", () -> (d = load_sim_data(P(1), :lagrangian); (typeof(d), d.metadata)))
try_("conv_E 1", () -> (d = load_sim_data(P(1), :eulerian, (3, 2)); (typeof(d), d.metadata)))
try_("conv_E 4", () -> (d = load_sim_data(P(4), :eulerian, (4, 3)); (typeof(d), keys(d.stats))))
try_("stats 1", () -> keys(load_sim_data(P(1)).stats))
try_("stats 4", () -> keys(load_sim_data(P(4)).stats))
try_("info 2", () -> get_sim_data_info(P(2)))
try_("table", () -> (t = sim_data_table(); [(r.format_version, r.postprocessed, r.solver) for r in eachrow(t)]))
h1 = calculate_hash(get_clean_params(P(1)))[1:10]
try_("prefix 1", () -> (e = load_sim_data(h1); sort(collect(keys(e)))))
h5 = calculate_hash(get_clean_params(P(5)))[1:10]
try_("prefix 5", () -> (e = load_sim_data(h5); [(k, typeof(v)) for (k, v) in e]))
try_("prefix 5 group usable", () -> (e = load_sim_data(h5); haskey(e, "grp/a") ? e["grp/a"] : (g = e["grp"]; g["a"])))
dir = joinpath(get_save_path(), "data")
stamps = Dict(f => mtime(joinpath(dir, f)) for f in readdir(dir))
try_("dryrun upgrade", () -> Dict(k => length(v) for (k, v) in upgrade_sim_data(; dry_run = true)))
try_("pipeline 8 cached", () -> (s = run_all_simulations(SimulationConfig(P8; sources = [joinpath(ARGS[1], "solver8.jl")]); calculate_stats = true); (length(s.cached), length(s.ran), length(s.changed))))
try_("unchanged files", () -> [f for f in readdir(dir) if get(stamps, f, 0) != mtime(joinpath(dir, f))])
try_("upgrade", () -> Dict(k => length(v) for (k, v) in upgrade_sim_data()))
for i in 1:7
    try_("after upgrade load $i", () -> (d = load_sim_data(P(i)); (size(d.u), d.metadata)))
end
try_("after upgrade 5 entries", () -> jldopen(f -> sort(collect(keys(f))), get_file_name(P(5)), "r"))
try_("after upgrade 1 entries", () -> jldopen(f -> sort(collect(keys(f))), get_file_name(P(1)), "r"))
try_("after upgrade table", () -> (t = sim_data_table(); [(r.format_version, r.postprocessed, r.solver) for r in eachrow(t)]))
