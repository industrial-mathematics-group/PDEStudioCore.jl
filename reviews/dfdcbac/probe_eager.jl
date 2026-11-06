# Typed containers convert a lazy range into an array *before* the whole-value size check runs.
using PDEStudioCore, Test
const S = PDEStudioCore
function run_old(tag, f)
    for s in ("Vector{Float16}[0:2^26]", "Dict{Int, Vector{Float16}}(1 => 0:2^26)")
        f(s)
        v = nothing
        el = @elapsed v = f(s); al = @allocated f(s)
        println(rpad(tag, 8), rpad(s, 42), " -> ", v isa String ? "String" : summary(v), "  ", round(el; digits = 3), " s  ", al ÷ 2^20, " MiB")
    end
end
for (tag, file) in (("f97198a", "old_f97198a_Serialization.jl"), ("8f39531", "old_8f39531_Serialization.jl"))
    mod = Module(Symbol("Old_", tag))
    Core.eval(mod, :(using PDEStudioCore: ParamDict, AbstractSimData; using SHA: sha256))
    Base.include(mod, joinpath(@__DIR__, file))
    Base.invokelatest(run_old, tag, Base.invokelatest(getglobal, mod, :str2val))
end
for k in (24, 26, 28)
    s = "Vector{Float16}[0:2^$k]"; str2val(s)
    el = @elapsed v = str2val(s); al = @allocated str2val(s)
    println(rpad("dfdcbac", 8), rpad(s, 42), " -> ", v isa String ? "String" : summary(v), "  ", round(el; digits = 3), " s  ", al ÷ 2^20, " MiB")
end
for s in ("Vector{Float32}[1:2^62]", "Vector{Float16}[0:2^40]")
    el = @elapsed v = str2val(s)
    println(rpad("dfdcbac", 8), rpad(s, 42), " -> ", v isa String ? "String" : summary(v), "  ", round(el; digits = 3), " s")
end
@testset "eager collection of a range is bounded" begin
    @test @allocated(str2val("Vector{Float16}[0:2^26]")) < 2^20
end
