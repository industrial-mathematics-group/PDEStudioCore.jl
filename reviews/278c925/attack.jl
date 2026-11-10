# Attacks on 278c925 with copies of the 0.4.4 files (ARGS[1] = d04 folder). Run with either src.
using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
PDEStudioCore.set_target_module!(@__MODULE__)
println("src: ", pathof(PDEStudioCore))
# a package type with its own serialization whose reading fails (e.g. a changed format)
struct Pkt; s::String; end
JLD2.writeas(::Type{Pkt}) = String
JLD2.wconvert(::Type{String}, p::Pkt) = p.s
const FAIL_READ = Ref(false)
JLD2.rconvert(::Type{Pkt}, s::String) = FAIL_READ[] ? error("Pkt: format changed") : Pkt(s)
P(i) = create_param_dict(:case => i)
noop(d) = nothing
function fresh()
    tmp = mktempdir(); cp(ARGS[1], joinpath(tmp, "s"); force = true); set_save_path!(joinpath(tmp, "s"))
end
function try_(label, f)
    try
        r = f(); println("OK   $label => ", r)
    catch e
        println("FAIL $label => ", sprint(showerror, e)[1:min(end, 250)])
    end
end
entries(p) = JLD2.jldopen(f -> sort(collect(keys(f))), get_file_name(p), "r")
quiet(f) = Base.CoreLogging.with_logger(f, Base.CoreLogging.SimpleLogger(stderr, Base.CoreLogging.Error))

println("\n## A. legacy file with an entry that can't be read")
fresh()
FAIL_READ[] = false
JLD2.jldopen(f -> (f["pkt"] = Pkt("x")), get_file_name(P(1)), "a+")
FAIL_READ[] = true
try_("A load", () -> load_sim_data(P(1)).metadata)
try_("A post-processing (nothing)", () -> quiet(() -> (s = run_all_simulations(SimulationConfig(P(1); postprocess = :noop)); (s.postprocessing, s.postprocessing_failed))))
try_("A entries after", () -> entries(P(1)))
try_("A save overwrite", () -> (save_sim_data(load_sim_data(P(1)); overwrite = true, verbose = false); entries(P(1))))
fresh(); JLD2.jldopen(f -> (FAIL_READ[] = false; f["pkt"] = Pkt("x")), get_file_name(P(1)), "a+"); FAIL_READ[] = true
try_("A upgrade", () -> quiet(() -> Dict(k => length(v) for (k, v) in upgrade_sim_data())))
try_("A pipeline after upgrade attempt", () -> quiet(() -> (s = run_all_simulations(SimulationConfig(P(1))); (length(s.cached), length(s.ran), length(s.failed)))))

println("\n## B. 0.4 user entries named \"postprocessed\"/\"provenance\" (dicts)")
fresh()
JLD2.jldopen(get_file_name(P(1)), "a+") do f
    f["postprocessed"] = Dict("smoothing" => "done", "passes" => 3)
    f["provenance"] = Dict("lab" => "B", "instrument" => Dict("id" => 7))
end
try_("B load", () -> (m = load_sim_data(P(1)).metadata; (m[:postprocessed], m[:provenance])))
try_("B upgrade", () -> quiet(() -> Dict(k => length(v) for (k, v) in upgrade_sim_data())))
try_("B after upgrade", () -> (m = load_sim_data(P(1)).metadata; (m[:postprocessed], m[:provenance])))

println("\n## C. 0.4 user entries \"format_version\" => 3 and \"metadata\"")
fresh()
JLD2.jldopen(get_file_name(P(1)), "a+") do f
    f["format_version"] = 3; f["metadata"] = "mine"
end
try_("C version", () -> JLD2.jldopen(PDEStudioCore._format_version, get_file_name(P(1)), "r"))
try_("C load", () -> load_sim_data(P(1)).metadata)
try_("C upgrade", () -> quiet(() -> Dict(k => length(v) for (k, v) in upgrade_sim_data(get_file_name(P(1))))))

println("\n## D. post-processing (nothing) on a 0.4 file: upgrade side effects")
fresh()
try_("D before", () -> (list_available_conversions(P(1)), entries(P(1))))
try_("D post", () -> quiet(() -> run_all_simulations(SimulationConfig(P(1); postprocess = :noop)).postprocessing))
try_("D after", () -> (list_available_conversions(P(1)), entries(P(1)), load_sim_data(P(1)).metadata))
try_("D dry run on a fresh copy writes nothing", () -> begin
    fresh(); m0 = mtime(get_file_name(P(1)))
    quiet(() -> run_all_simulations(SimulationConfig(P(1); postprocess = :noop); dry_run = true))
    (mtime(get_file_name(P(1))) == m0, entries(P(1)) == entries(P(1)))
end)

println("\n## E. v3 file whose metadata holds a value that can't be read")
set_save_path!(mktempdir())
pe = create_param_dict(:case => :e)
FAIL_READ[] = false
save_sim_data(create_sim_data(collect(0.0:0.5:1.0), [SVector(1.0) for i in 1:3, j in 1:2], [0.0, 1.0], pe;
                              metadata = Dict(:pkt => Pkt("x"), :note => "n")); verbose = false)
FAIL_READ[] = true
try_("E load", () -> load_sim_data(pe).metadata)
try_("E exists", () -> does_sim_data_exist(pe))
try_("E table", () -> quiet(() -> size(sim_data_table())))
try_("E pipeline", () -> quiet(() -> (s = run_all_simulations(SimulationConfig(pe; postprocess = :noop)); (length(s.cached), s.postprocessing, s.postprocessing_failed))))
FAIL_READ[] = false

println("\n## F. sim_data_table with a corrupt file")
fresh()
d = joinpath(get_save_path(), "data")
f1 = get_file_name(P(1)); write(f1 * ".x", read(f1)[1:div(filesize(f1), 2)]); mv(f1 * ".x", f1; force = true)
write(joinpath(d, "2026-01-01_00-00-00_000_" * "ab"^32 * ".jld2"), "not a jld2 file")
try_("F table", () -> quiet(() -> (t = sim_data_table(); (size(t), t.kind))))
