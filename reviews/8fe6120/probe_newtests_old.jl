# Do the new tests of 8fe6120 fail at 2cef67f? (old Serialization.jl loaded into a module.)
# The NTuple{2^62, Int} test is run separately (it segfaults at 2cef67f). Run under `ulimit -v`.
using PDEStudioCore, Test
mod = Module(:Old_2cef67f)
Core.eval(mod, :(using PDEStudioCore: ParamDict, AbstractSimData; using SHA: sha256))
Base.include(mod, joinpath(@__DIR__, "old_2cef67f_Serialization.jl"))
old = Base.invokelatest(getglobal, mod, :str2val)
lit(s) = old(s)
old("1"); str2val("1")
for (name, f) in (("HEAD", str2val), ("2cef67f", old))
    try; @testset "new tests at $name" begin
        a1 = @allocated(f("Vector{Float16}[0:2^26]"))
        a2 = @allocated(f("Vector{Float16}[0:2^26]"))
        println("$name: Vector{Float16}[0:2^26] allocates ", a1, " (first call), ", a2, " (second call)")
        @test @allocated(f("Vector{Float16}[0:2^26]")) < 2^20
        s50 = "Vector{Float64}[" * join(fill("1:10^6", 50), ", ") * "]"
        f(s50)
        a = @allocated(v = f(s50))
        println("$name: 50 ranges in Vector{Float64}[...] -> ", v isa String ? "String" : summary(v), ", allocated ", round(a / 2^20; digits = 1), " MiB")
        @test v isa String
        @test f("[1:3, 4:6]") isa String && f("1:3") == 1:3
        @test f("Array{Int, 2}") == Matrix{Int} && f("Val{2^62}()") == Val{2^62}()
        @test f("reshape([1, 2], (-1, -2))") isa String && f("reshape([1, 2], (1, 2))") == [1 2]
        # the variant of the previous review's finding 3 (ranges, which Base reshapes with negative dims)
        r = f("reshape(1:6, (-2, -3))")
        println("$name: reshape(1:6, (-2, -3)) -> ", typeof(r))
        @test r isa String
    end; catch; end
end
