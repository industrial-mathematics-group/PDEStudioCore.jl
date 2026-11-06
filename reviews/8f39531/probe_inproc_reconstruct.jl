# Cheaper alternative to the two-process test: a type in an anonymous module is unknown to JLD2 when reading.
using Test, Logging
include(joinpath(@__DIR__, "rec_common.jl"))
@testset "in-process reconstruction" begin
    m = Module(:ForeignMod)
    Core.eval(m, :(struct ForeignEntry; a::Int; end))
    f = joinpath(mktempdir(), "x.jld2")
    jldsave(f; foo = Base.invokelatest(m.ForeignEntry, 7))
    v = JLD2.load(f, "foo")
    println("loaded as ", typeof(v))
    @test PDEStudioCore._is_reconstructed(v)
end
jl = Base.julia_cmd(); proj = Base.active_project()
t = @elapsed run(`$jl --project=$proj -e "using PDEStudioCore; using PDEStudioCore.JLD2; struct ForeignEntry; a::Int; end"`)
println("one subprocess as in test_data.jl: $t s")
