# Where the time goes for deep NamedTuples and distinct types; same cases on the code of the active project
using PDEStudioCore
using PDEStudioCore: _reconstructed_type as rt
println("PDEStudioCore at ", pathof(PDEStudioCore))
tm(label, f) = (f(); t = @elapsed(f()); a = @allocated(f()); println(rpad(label, 60), round(t * 1e3; sigdigits = 3), " ms, ", round(a / 2^20; sigdigits = 3), " MiB"))
mk(d) = d == 0 ? 1.0 : NamedTuple{ntuple(i -> Symbol("f", i), 10)}(ntuple(_ -> mk(d - 1), 10))
nt = mk(4)
tm("string(typeof(deep NT 4x10))", () -> string(typeof(nt)))
tm("rt(deep NT 4x10)", () -> rt(nt))
tm("rt(Any[deep NT 4x10])", () -> rt(Any[nt]))
v = Any[Val(i) for i in 1:2000]
tm("string.(typeof.(2000 Val types))", () -> map(x -> string(typeof(x)), v))
tm("rt(Any[2000 Val types])", () -> rt(v))
tv = Any[ntuple(_ -> 0.0, n) for n in 1:300]
tm("rt(Any[NTuple{n,Float64} for n in 1:300])", () -> rt(tv))
recs = Any[NamedTuple{(Symbol("run", i), :dt)}((1.0, 0.1)) for i in 1:2000]
tm("rt(Any[2000 NamedTuples with distinct names])", () -> rt(recs))
