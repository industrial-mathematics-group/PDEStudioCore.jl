# ARGS: save path, step. Same data folder used by the new (a42a9e0) and the old (2818d7e) code.
using PDEStudioCore, StaticArrays, Logging
const JLD2 = PDEStudioCore.JLD2
set_save_path!(ARGS[1])
const OFFSET = Ref(parse(Float64, ARGS[3]))
mix_solver(p) = (x = collect(range(0.0, 1.0, length = p[:n])); create_sim_data(x, fill(SVector(OFFSET[]), length(x), 2), [0.0, 1.0], p))
const CALLS = Ref(0)
mark_post(d) = (CALLS[] += 1; d.u .= map(v -> v .+ 100, d.u); true)
cfg = SimulationConfig(Dict(:sim_func_name => :mix_solver, :n => 4); postprocess = :mark_post)
p = only(generate_tasks(cfg))
step = ARGS[2]
with_logger(NullLogger()) do
    if step == "new"
        run_all_simulations(cfg)
    elseif step == "old-overwrite"      # old code: new data, without post-processing
        run_all_simulations(cfg; force_overwrite = true, post_process = false)
    end
end
f = get_file_name(p)
r = JLD2.jldopen(io -> (haskey(io, "postprocessed") ? io["postprocessed"]["name"] : nothing,
                        haskey(io, "provenance") ? io["provenance"]["created"] : nothing), f, "r")
println(rpad(step, 14), " PDEStudioCore ", pkgversion(PDEStudioCore), " src=", dirname(pathof(PDEStudioCore))[end-20:end],
        ": u[1] = ", load_sim_data(p).u[1][1], " post calls = ", CALLS[], " record = ", r[1], " provenance created = ", r[2])
