# dry_run: writes nothing? reports what the real run does?
include(joinpath(@__DIR__, "common.jl"))
const CALLS = Ref(0); set_stat_preset!("hyperbolic")
cnt_post(d) = (CALLS[] += 1; nothing)
cfg = SimulationConfig(Dict(:sim_func_name => :lin_solver, :n => 4); varied = Dict(:n => [4, 5, 6, 7]), postprocess = :cnt_post)
tasks = generate_tasks(cfg)
with_logger(NullLogger()) do; run_all_simulations(cfg; post_process = false); end   # no stats, no record
# task 1 -> version 0 file (only the data), task 2 -> version 1 (no format_version / axes)
p0, p1 = tasks[1], tasks[2]
d0 = load_sim_data(p0); f0 = get_file_name(p0); rm(f0); JLD2.jldopen(f -> (f["raw"] = d0), f0, "w")
JLD2.jldopen(f -> (delete!(f, "format_version"); delete!(f, "dim_keys"); delete!(f, "time_dim")), get_file_name(p1), "a+")
rm(get_file_name(tasks[4]))
dir = joinpath(get_save_path(), "data")
snap() = sort([(f, mtime(joinpath(dir, f)), filesize(joinpath(dir, f))) for f in readdir(dir)])
before = snap()
s = with_logger(NullLogger()) do; run_all_simulations(cfg; calculate_stats = true, dry_run = true); end
println("dry run wrote nothing: ", snap() == before, "   post calls: ", CALLS[])
println("dry : ran=", length(s.ran), " cached=", length(s.cached), " stats=", s.stats, " post=", s.postprocessing)
r = with_logger(NullLogger()) do; run_all_simulations(cfg; calculate_stats = true); end
println("real: ran=", length(r.ran), " cached=", length(r.cached), " stats=", r.stats, " post=", r.postprocessing)
s2 = with_logger(NullLogger()) do; upgrade_sim_data(dry_run = true); end
println("upgrade dry run after: ", Dict(k => length(v) for (k, v) in s2))
# unreadable raw: dry run of upgrade_sim_data vs real
q = create_param_dict(:n => 11); fq = joinpath(dir, "2020-01-01_00-00-00_000_" * PDEStudioCore._param_hash(q) * ".jld2")
JLD2.jldopen(f -> (f["raw"] = "not a dataset"), fq, "w")
println("upgrade_sim_data(fq; dry_run) = ", findfirst(v -> fq in v, upgrade_sim_data(fq; dry_run = true)),
        "  real = ", findfirst(v -> fq in v, with_logger(() -> upgrade_sim_data(fq), NullLogger())))
