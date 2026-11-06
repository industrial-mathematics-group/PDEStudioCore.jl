# _reconstructed_type at bc0e729: findings 1/2 of reviews/64a39da.md re-run, plus regressions
using PDEStudioCore, StaticArrays, Test, Logging
using PDEStudioCore: JLD2, _reconstructed_type as rt, _may_hide
set_save_path!(mktempdir())
anon = Module(); Core.eval(anon, :(struct Hidden; a::Int; end))
Core.eval(anon, :(struct Box; v::Any; end))   # a loaded struct with an untyped field
H(i) = Base.invokelatest(anon.Hidden, i)
f = joinpath(mktempdir(), "h.jld2")
roundtrip(v) = (JLD2.jldsave(f; v = v); JLD2.load(f, "v"))
show_rt(label, v) = (println(rpad(label, 66), repr(rt(v))); flush(stdout))

println("== false positives (should all be nothing)"); flush(stdout)
MyJLD2 = Module(:MyJLD2); Core.eval(MyJLD2, :(struct Reconstructed; end))
for (label, v) in [
        "Dict{Symbol,Any} mixed" => Dict{Symbol, Any}(:a => 1, :b => "x", :c => [1.0], :d => Float64, :e => Any[Int, :s]),
        "nested Any vectors" => Any[Any[Any[Any[Any[1]]]]],
        "String with JLD2.ReconstructedMutable" => "JLD2.ReconstructedMutable{:X}",
        "Any[String/Symbol with JLD2.UnknownType]" => Any["JLD2.UnknownType", Symbol("JLD2.Serialized")],
        "Types as values" => Any[Float64, Vector{Any}, Union{Int, Missing}, Type, DataType, Any, Union{}, Vector, Tuple{Vararg{Int}}],
        "Vector{Union{Missing,Float64}} 10^7" => Union{Missing, Float64}[i for i in 1:10^7],
        "tuple / NamedTuple / Pair" => ((1, 2.0, "a"), (a = 1, b = Any[:x]), :p => Any[1]),
        "Set{Any}, Dict{Any,Any} keys" => (Set{Any}([1, "a"]), Dict{Any, Any}((1, 2) => 3, "k" => [1])),
        "after roundtrip: Dict{Symbol,Any}" => roundtrip(Dict{Symbol, Any}(:a => 1, :T => Float32, :v => Any[1, "a"])),
        "after roundtrip: nested NamedTuples" => roundtrip((a = (b = (c = (d = Any[1, "x"],),),),)),
        "after roundtrip: Vector{Vector{Any}}" => roundtrip([Any[1, :a], Any["b"]]),
        "MyJLD2.Reconstructed() (was a false positive)" => Base.invokelatest(MyJLD2.Reconstructed),
        "Any[MyJLD2.Reconstructed]" => Any[MyJLD2.Reconstructed],
    ]
    show_rt(label, v)
end

println("== true positives after a JLD2 round trip (should name Hidden)"); flush(stdout)
for (label, v) in [
        "Hidden" => H(1), "type Hidden" => anon.Hidden, "Any[1, Hidden]" => Any[1, H(2)],
        "Dict{Symbol,Any}(:h => type)" => Dict{Symbol, Any}(:h => anon.Hidden),
        "Any[Any[(1, type)]]" => Any[Any[(1, anon.Hidden)]],
        "Vector{Type}[type]" => Type[anon.Hidden],
        "depth 4: Any[Any[Any[Any[h]]]]" => Any[Any[Any[Any[H(1)]]]],
        "Vector{Hidden}" => [H(1)],
        "Union{Nothing,Hidden}[]" => Union{Nothing, anon.Hidden}[nothing, H(1)],
    ]
    show_rt(label, roundtrip(v))
end
println("== previous false negatives (finding 1)"); flush(stdout)
for (label, v) in [
        "Vector{Vector{Any}}: [Any[h]]" => [Any[H(1)]],
        "Dict{String, Dict{Symbol,Any}}" => Dict("run" => Dict{Symbol, Any}(:solver => anon.Hidden)),
        "Dict{Symbol, Vector{Any}}" => Dict(:v => Any[H(1)]),
        "NamedTuple (a = Any[h],)" => (a = Any[H(1)],),
        "Pair :a => Any[h]" => (:a => Any[H(1)]),
        "Set{Any}" => Set{Any}([H(1)]),
        "depth 5: Any[Any[Any[Any[Any[h]]]]]" => Any[Any[Any[Any[Any[H(1)]]]]],
        "Any vector, h at index 10^4+1" => (v = Any[i for i in 1:10^4]; push!(v, H(1)); v),
        "Dict{Symbol,Any} with 10^4+ keys, one value Hidden" =>
            (d = Dict{Symbol, Any}(Symbol("k", i) => i for i in 1:10_001); d[:h] = H(1); d),
        "Dict{Symbol,Any} with 6000 keys, one value Hidden" =>
            (d = Dict{Symbol, Any}(Symbol("k", i) => i for i in 1:6000); d[:h] = H(1); d),
    ]
    show_rt(label, roundtrip(v))
end
println("== new cut-offs and remaining gaps"); flush(stdout)
for (label, v) in [
        "Any vector, h at index 10^5+1" => (v = Any[i for i in 1:10^5]; push!(v, H(1)); v),
        "Any vector of 10^5 Float64 with h at 2" => (v = Any[Float64(i) for i in 1:10^5]; v[2] = H(1); v),
        "Dict{Symbol,Any} 2*10^5 keys, 100 values Hidden" =>
            (d = Dict{Symbol, Any}(Symbol("k", i) => i for i in 1:2 * 10^5); for j in 1:100; d[Symbol("h", j)] = H(j); end; d),
        "Dict{Any,Any} keys Hidden" => Dict{Any, Any}(H(1) => 1),
        "Set{Any} in Dict{Symbol,Any}" => Dict{Symbol, Any}(:s => Set{Any}([H(1)])),
        "loaded struct Box(v = h)" => Base.invokelatest(anon.Box, H(1)),
        "Any[Box(type)]" => Any[Base.invokelatest(anon.Box, anon.Hidden)],
        "Vector^5{Any}: [[[[[Any[h]]]]]]" => [[[[Any[H(1)]]]]],
        "Vector^6{Any}" => [[[[[Any[H(1)]]]]]],
        "NamedTuple nested 5 deep" => (a = (b = (c = (d = (e = H(1),),),),),),
        "budget used up by an earlier entry of a tuple" => (Any[i for i in 1:10^5], Any[H(1)]),
        "Any[] of 10^5 tiny Any[], h in the last" => (v = Any[Any[i] for i in 1:10^5]; v[end] = Any[H(1)]; v),
    ]
    show_rt(label, roundtrip(v))
end

println("== cost (warm; each case twice, second timed)"); flush(stdout)
function time_rt(label, mk)
    v = mk(); GC.gc(); rt(v)
    t = @elapsed(rt(v)); a = @allocated(rt(v))
    println(rpad(label, 66), round(t * 1e3; sigdigits = 3), " ms, ", round(a / 2^20; sigdigits = 3), " MiB"); flush(stdout)
end
time_rt("Any[Float64 x 10^6]", () -> Any[rand() for _ in 1:10^6])
time_rt("Vector{Union{Missing,Float64}} 10^7", () -> Union{Missing, Float64}[i for i in 1:10^7])
time_rt("Vector{Union{Missing,Float64}} 10^7 after roundtrip", () -> roundtrip(Union{Missing, Float64}[i for i in 1:10^7]))
time_rt("Any[1000 x Any[1000 Float64]]", () -> Any[Any[rand() for _ in 1:1000] for _ in 1:1000])
time_rt("Any[100 x Any[100 x Any[100]]]", () -> Any[Any[Any[rand() for _ in 1:100] for _ in 1:100] for _ in 1:100])
time_rt("Any[30 x ... x Any[30]] depth 4 (8.1e5 leaves)", () -> Any[Any[Any[Any[rand() for _ in 1:30] for _ in 1:30] for _ in 1:30] for _ in 1:30])
time_rt("Dict{Symbol,Any} 10^6 entries", () -> Dict{Symbol, Any}(Symbol("k", i) => rand() for i in 1:10^6))
time_rt("Dict{Any,Any} 10^6 entries", () -> Dict{Any, Any}(i => rand() for i in 1:10^6))
time_rt("Vector{Float64} 10^8 (concrete)", () -> zeros(10^8))
time_rt("Any[] of 10^5 distinct-type values (Val{i}())", () -> Any[Val(i) for i in 1:10^5])
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
