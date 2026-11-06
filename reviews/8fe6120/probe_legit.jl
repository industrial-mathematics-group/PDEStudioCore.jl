# Legitimate values that val2str writes with an integer type parameter above 256: do they still round-trip?
using PDEStudioCore, StaticArrays, Test
mod = Module(:Old_2cef67f)
Core.eval(mod, :(using PDEStudioCore: ParamDict, AbstractSimData; using SHA: sha256; using StaticArrays))
Base.include(mod, joinpath(@__DIR__, "old_2cef67f_Serialization.jl"))
old = Base.invokelatest(getglobal, mod, :str2val)
vals = Any[[ntuple(i -> 1.0, 300)], [ntuple(i -> 1.0, 256)], NTuple{300, Float64}, [SVector(ntuple(i -> 1.0, 300))],
           Dict(:a => ntuple(i -> i, 300)), ntuple(i -> i, 300), [zeros(1, 1)], Val(300), [Val(300)], Array{Float64, 300},
           [SMatrix{16, 16}(zeros(256))], [SMatrix{17, 17}(zeros(289))]]
for v in vals
    s = val2str(v)
    new, o = str2val(s), Base.invokelatest(old, s)
    println(rpad(first(s, 60), 62), " HEAD: ", rpad(new isa String ? "String" : string(typeof(new))[1:min(end, 40)], 42),
            " 2cef67f: ", o isa String ? "String" : string(typeof(o))[1:min(end, 40)])
end
