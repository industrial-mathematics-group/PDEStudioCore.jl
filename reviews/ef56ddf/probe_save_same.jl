# save_sim_data deciding "same data" with _is_native_representation
include(joinpath(@__DIR__, "common.jl"))
q(f) = with_logger(NullLogger()) do; f(); end
# (a) the docs' idempotent pattern: a post-processor that only sets a statistic (advanced_config.md `add_maximum`)
const CALLS = Ref(0)
function add_max(d)
    CALLS[] += 1
    add_stat!(d, :maximum, maximum(v -> v[1], d.u), Symbol[]); true
end
cfg = SimulationConfig(Dict(:sim_func_name => :lin_solver, :n => 4); postprocess = :add_max)
p = only(generate_tasks(cfg))
q(() -> run_all_simulations(cfg))
println("(a) after pipeline: stats=", sort(collect(keys(load_sim_data(p).stats))), " calls=", CALLS[])
fresh = lin_solver(copy(p))            # recompute by hand (same deterministic solver), save over it
q(() -> save_sim_data(fresh; overwrite = true))
println("    after save_sim_data(fresh recompute; overwrite): stats=", sort(collect(keys(load_sim_data(p).stats))),
        " record=", rec(get_file_name(p)) === nothing ? nothing : rec(get_file_name(p))["name"])
s = q(() -> run_all_simulations(cfg))
println("    next pipeline run: post=", s.postprocessing, " stats=", sort(collect(keys(load_sim_data(p).stats))), " calls=", CALLS[])
# (c) cost: a large dataset
big = create_param_dict(:sim_func_name => :lin_solver, :n => 4, :big => true)
xb = collect(range(0.0, 1.0, length = 4000)); tb = collect(range(0.0, 1.0, length = 2000))
db = create_sim_data(xb, fill(SVector(1.0), 4000, 2000), tb, big)
q(() -> save_sim_data(db; overwrite = true))
db.u[1] = SVector(2.0)
GC.gc()
t_new = @elapsed q(() -> save_sim_data(db; overwrite = true))   # differs: compare + write
t_same = @elapsed q(() -> save_sim_data(db; overwrite = true))  # same: compare + write
t_cmp = @elapsed PDEStudioCore._is_native_representation(get_file_name(big), db)
println("(c) ", round(filesize(get_file_name(big)) / 2^20, digits = 1), " MB: save(overwrite) ", round(t_same, digits = 2), " s, of which the comparison ", round(t_cmp, digits = 2), " s")
