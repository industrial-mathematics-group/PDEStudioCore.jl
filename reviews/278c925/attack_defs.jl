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

