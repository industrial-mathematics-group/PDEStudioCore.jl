# The new NTuple{2^62, Int} test against 2cef67f's str2val (expected: the process crashes).
using PDEStudioCore
mod = Module(:Old_2cef67f)
Core.eval(mod, :(using PDEStudioCore: ParamDict, AbstractSimData; using SHA: sha256))
Base.include(mod, joinpath(@__DIR__, "old_2cef67f_Serialization.jl"))
old = Base.invokelatest(getglobal, mod, :str2val)
println("2cef67f: ", typeof(old("NTuple{2^62, Int}")))
