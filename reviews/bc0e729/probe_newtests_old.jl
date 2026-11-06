# The tests added in bc0e729 (reconstruction part), run against the code of the checkout given by the project
using PDEStudioCore, Test, Logging
println("PDEStudioCore at ", pathof(PDEStudioCore))
anon = Module(); Core.eval(anon, :(struct Hidden; a::Int; end))
hidden_file = joinpath(mktempdir(), "hidden.jld2")
H = Base.invokelatest(anon.Hidden, 3)
big = Dict{Symbol, Any}(Symbol("k", i) => i for i in 1:10^4)
big[:z] = H
PDEStudioCore.JLD2.jldsave(hidden_file; vv = [Any[H]], dd = Dict("run" => Dict{Symbol, Any}(:h => anon.Hidden)),
                           nt = (a = 1, b = Any[H]), pr = :p => Any[H], big = big)
for k in ("vv", "dd", "nt", "pr", "big")
    println(rpad("_is_reconstructed($k)", 50), PDEStudioCore._is_reconstructed(PDEStudioCore.JLD2.load(hidden_file, k)))
end
nested = Any[Any[Any[Any[0.0 for _ in 1:30] for _ in 1:30] for _ in 1:30] for _ in 1:30]
PDEStudioCore._reconstructed_type(nested)
println(rpad("@elapsed nested < 0.5", 50), (t = @elapsed(PDEStudioCore._reconstructed_type(nested)); (t, t < 0.5)))
println(rpad("!_is_reconstructed(\"JLD2.ReconstructedStatic\")", 50), !PDEStudioCore._is_reconstructed("JLD2.ReconstructedStatic"))
println(rpad("!_is_reconstructed(:MyJLD2)", 50), !PDEStudioCore._is_reconstructed(:MyJLD2))
MyJLD2 = Module(:MyJLD2); Core.eval(MyJLD2, :(struct Reconstructed; end))
println(rpad("!_is_reconstructed(MyJLD2.Reconstructed()) (real anchoring test)", 50),
        !PDEStudioCore._is_reconstructed(Base.invokelatest(MyJLD2.Reconstructed)))
dest = joinpath(mktempdir(), "dest.jld2")
logger = Test.TestLogger(min_level = Logging.Warn)
with_logger(logger) do
    PDEStudioCore.JLD2.jldopen(dest, "w") do d
        PDEStudioCore.JLD2.jldopen(hidden_file, "r") do src
            PDEStudioCore._copy_entry!(d, src, "vv")
        end
    end
end
println(rpad("_copy_entry!(vv) warns naming Hidden", 50), any(r -> occursin(r"contains a type that isn't loaded.*Hidden", string(r.message)), logger.logs))
