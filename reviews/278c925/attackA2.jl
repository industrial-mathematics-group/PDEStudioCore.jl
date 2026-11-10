include(joinpath(@__DIR__, "attack_defs.jl"))
fresh()
FAIL_READ[] = false
JLD2.jldopen(f -> (f["pkt"] = Pkt("x")), get_file_name(P(1)), "a+")
FAIL_READ[] = true
try
    save_sim_data(load_sim_data(P(1)); overwrite = true, verbose = false)
catch e
    bt = catch_backtrace()
    for fr in stacktrace(bt)
        occursin("/src/", string(fr.file)) && println(fr.func, " ", basename(string(fr.file)), ":", fr.line)
    end
end
# E: what pass 1 did
set_save_path!(mktempdir())
pe = create_param_dict(:case => :e)
FAIL_READ[] = false
save_sim_data(create_sim_data(collect(0.0:0.5:1.0), [SVector(1.0) for i in 1:3, j in 1:2], [0.0, 1.0], pe; metadata = Dict(:pkt => Pkt("x"))); verbose = false)
FAIL_READ[] = true
s = quiet(() -> run_all_simulations(SimulationConfig(pe)))
println("E pass 1: ran ", length(s.ran), " cached ", length(s.cached), " failed ", s.failed, " stats ", s.stats, " ", s.stats_failed)
