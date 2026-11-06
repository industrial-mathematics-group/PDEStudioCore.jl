# The two contrived extremes of probe_reconstructed3.jl, on the code of the active project
using PDEStudioCore
using PDEStudioCore: _reconstructed_type as rt
println("PDEStudioCore at ", pathof(PDEStudioCore))
function time_rt(label, mk)
    v = mk(); GC.gc(); rt(v)
    t = @elapsed(rt(v)); a = @allocated(rt(v))
    println(rpad(label, 72), round(t * 1e3; sigdigits = 3), " ms, ", round(a / 2^20; sigdigits = 3), " MiB")
end
time_rt("Any[10^5 x Vector{NTuple{10,NTuple{10,NTuple{10,Float64}}}}()]",
        () -> Any[Vector{NTuple{10, NTuple{10, NTuple{10, Float64}}}}(undef, 0) for _ in 1:10^5])
time_rt("Any[10^5 x Dict{Symbol,NTuple{20,NTuple{20,NTuple{20,Float64}}}}()]",
        () -> Any[Dict{Symbol, NTuple{20, NTuple{20, NTuple{20, Float64}}}}() for _ in 1:10^5])
