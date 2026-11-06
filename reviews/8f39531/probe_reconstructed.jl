# Process A writes user entries of types process B lacks; B rewrites the data; C (with the types) reads them back.
using Test, Logging
include(joinpath(@__DIR__, "rec_common.jl"))
dir = mktempdir()
jl = Base.julia_cmd(); proj = Base.active_project()
run(`$jl --project=$proj $(joinpath(@__DIR__, "rec_a.jl")) $dir`)
set_save_path!(dir)
sim = load_sim_data(P)
logger = Test.TestLogger(min_level = Logging.Warn)
with_logger(logger) do
    save_sim_data(sim; overwrite = true)
end
warned = [m.message for m in logger.logs if occursin("isn't loaded", m.message)]
println("PDEStudioCore warnings: ", length(warned))
foreach(w -> println("  ", first(w, 90)), warned)
println("all warnings: ", length(logger.logs))
println("--- process C (types defined):")
run(`$jl --project=$proj $(joinpath(@__DIR__, "rec_c.jl")) $dir`)
