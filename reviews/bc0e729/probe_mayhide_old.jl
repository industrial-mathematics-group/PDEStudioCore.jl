# The repeated-_may_hide cases on the code of the active project (64a39da vs bc0e729)
using PDEStudioCore
using PDEStudioCore: _reconstructed_type as rt
println("PDEStudioCore at ", pathof(PDEStudioCore))
function time_rt(label, mk)
    v = mk(); GC.gc(); rt(v)
    t = @elapsed(rt(v)); a = @allocated(rt(v))
    println(rpad(label, 72), round(t * 1e3; sigdigits = 3), " ms, ", round(a / 2^20; sigdigits = 3), " MiB")
end
time_rt("Any[10^4 x [NTuple{100,Float64}]]", () -> Any[[ntuple(_ -> 0.0, 100)] for _ in 1:10^4])
time_rt("Any[10^4 x [NamedTuple with 50 Float64 fields]]", () -> Any[[NamedTuple{ntuple(i -> Symbol("f", i), 50)}(ntuple(_ -> 0.0, 50))] for _ in 1:10^4])
time_rt("Any[10^4 x Vector{NTuple{10,NTuple{10,NTuple{10,Float64}}}}()]",
        () -> Any[Vector{NTuple{10, NTuple{10, NTuple{10, Float64}}}}(undef, 0) for _ in 1:10^4])
