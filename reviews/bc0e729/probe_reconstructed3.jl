# _reconstructed_type at bc0e729: findings 1/2 of reviews/64a39da.md re-run, plus regressions
using PDEStudioCore, StaticArrays, Test, Logging
using PDEStudioCore: JLD2, _reconstructed_type as rt, _may_hide
set_save_path!(mktempdir())
anon = Module(); Core.eval(anon, :(struct Hidden; a::Int; end))
Core.eval(anon, :(struct Box; v::Any; end))   # a loaded struct with an untyped field
H(i) = Base.invokelatest(anon.Hidden, i)
f = joinpath(mktempdir(), "h.jld2")
roundtrip(v) = (JLD2.jldsave(f; v = v); JLD2.load(f, "v"))
function time_rt(label, mk)
    v = mk(); GC.gc(); rt(v)
    t = @elapsed(rt(v)); a = @allocated(rt(v))
    println(rpad(label, 66), round(t * 1e3; sigdigits = 3), " ms, ", round(a / 2^20; sigdigits = 3), " MiB"); flush(stdout)
end
time_rt("Any[] of 2000 distinct-type values (Val{i}())", () -> Any[Val(i) for i in 1:2000])
time_rt("deep NamedTuple 4 levels x 10 fields", () -> (mk(d) = d == 0 ? 1.0 : NamedTuple{ntuple(i -> Symbol("f", i), 10)}(ntuple(_ -> mk(d - 1), 10)); mk(4)))
time_rt("NTuple{10^4, Float64} value", () -> ntuple(i -> Float64(i), 10^4))
println("-- _may_hide on wide/deep Tuple types"); flush(stdout)
for (label, T) in [("NTuple{1000,Float64}", NTuple{1000, Float64}),
                   ("NTuple{30,NTuple{30,NTuple{30,Float64}}}", NTuple{30, NTuple{30, NTuple{30, Float64}}}),
                   ("NTuple{10,NTuple{10,NTuple{10,NTuple{10,NTuple{10,Float64}}}}}", NTuple{10, NTuple{10, NTuple{10, NTuple{10, NTuple{10, Float64}}}}}),
                   ("Tuple of 5000 distinct field types", Tuple{[isodd(i) ? Int : Float64 for i in 1:5000]...})]
    _may_hide(T); t = @elapsed(_may_hide(T)); a = @allocated(_may_hide(T))
    println(rpad("   _may_hide($label)", 70), _may_hide(T), "  ", round(t * 1e3; sigdigits = 3), " ms, ", round(a / 2^20; sigdigits = 3), " MiB")
end
println("-- repeated _may_hide: Any[] of N vectors whose eltype is a wide tuple type (one _may_hide per inner vector)"); flush(stdout)
time_rt("Any[10^4 x [NTuple{100,Float64}]]", () -> Any[[ntuple(_ -> 0.0, 100)] for _ in 1:10^4])
time_rt("Any[10^4 x Vector{NTuple{10,NTuple{10,NTuple{10,Float64}}}}(undef,0)]",
        () -> Any[Vector{NTuple{10, NTuple{10, NTuple{10, Float64}}}}(undef, 0) for _ in 1:10^4])
time_rt("Any[10^5 x Vector{NTuple{10,NTuple{10,NTuple{10,Float64}}}}(undef,0)]",
        () -> Any[Vector{NTuple{10, NTuple{10, NTuple{10, Float64}}}}(undef, 0) for _ in 1:10^5])
time_rt("Any[10^5 x Dict{Symbol,NTuple{20,NTuple{20,NTuple{20,Float64}}}}()]",
        () -> Any[Dict{Symbol, NTuple{20, NTuple{20, NTuple{20, Float64}}}}() for _ in 1:10^5])

println("== cycles"); flush(stdout)
a = Any[]; push!(a, a); println("   self-referential Any vector: ", repr(rt(a)), "  ", round(@elapsed(rt(a)) * 1e3; sigdigits = 3), " ms")
d = Dict{Symbol, Any}(); d[:self] = d; d[:b] = d; println("   self-referential Dict: ", repr(rt(d)))
w = Any[]; for _ in 1:50; push!(w, w); end
println("   Any vector holding itself 50 times (50^4 paths): ", repr(rt(w)), "  ", round(@elapsed(rt(w)) * 1e3; sigdigits = 3), " ms"); flush(stdout)
r = Ref{Any}(); r[] = r; println("   self-referential Ref{Any}: ", repr(rt(r)))

println("== end to end: carried-over metadata during save_sim_data(overwrite = true)"); flush(stdout)
x = collect(0.0:0.5:1.0)
p = create_param_dict(:case => "e2e")
md = Dict("top" => Dict{Symbol, Any}(:h => anon.Hidden), "nested" => Dict("run" => Dict{Symbol, Any}(:solver => anon.Hidden)),
          "vv" => [Any[H(3)]], "nt" => (a = 1, b = Any[H(1)]), "set" => Set{Any}([H(2)]), "plain" => Dict(:a => [1.0]),
          "box" => Base.invokelatest(anon.Box, H(4)))
save_sim_data(create_sim_data(x, rand(3, 2), [0.0, 1.0], p); metadata = md, verbose = false)
logger = Test.TestLogger(min_level = Logging.Warn)
with_logger(logger) do
    save_sim_data(load_sim_data(p); overwrite = true, verbose = false)
end
warned = [match(r"Entry '([^']+)'.*\((.*)\)", string(r.message)) for r in logger.logs]
println("   warned entries: ", sort([m.captures[1] for m in warned if m !== nothing])); flush(stdout)
for m in warned; m === nothing || println("     ", m.captures[1], ": ", first(m.captures[2], 90)); end
