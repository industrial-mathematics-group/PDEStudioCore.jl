# Do the two new str2val tests fail at dfdcbac? (old Serialization.jl loaded into a module)
# Run under `ulimit -v` so that the old code cannot fill 64 GiB.
using PDEStudioCore, Test
mod = Module(:Old_dfdcbac)
Core.eval(mod, :(using PDEStudioCore: ParamDict, AbstractSimData; using SHA: sha256))
Base.include(mod, joinpath(@__DIR__, "old_dfdcbac_Serialization.jl"))
old = Base.invokelatest(getglobal, mod, :str2val)
@testset "new tests against dfdcbac" begin
    t = @elapsed(v = old("Vector{Float32}[1:2^34]"))
    println("old: Vector{Float32}[1:2^34] -> ", v isa String ? "String" : summary(v), " in ", round(t; digits = 3), " s")
    @test t < 1                                                  # passes at dfdcbac if malloc fails (ulimit) -> not a regression test there
    @test old("reshape(1:0, (2^32, 2^32))") isa String           # expected to fail at dfdcbac
    # the cheap regression test suggested in the previous review
    @test @allocated(old("Vector{Float16}[0:2^26]")) < 2^20      # expected to fail at dfdcbac
end
@testset "same tests at 2cef67f" begin
    @test @elapsed(str2val("Vector{Float32}[1:2^34]")) < 1
    @test str2val("reshape(1:0, (2^32, 2^32))") isa String
    @test @allocated(str2val("Vector{Float16}[0:2^26]")) < 2^20
end
