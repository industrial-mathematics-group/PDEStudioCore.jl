# _reconstructed_type: false positives, false negatives, cost bounds, cycles, end-to-end warning
using PDEStudioCore, StaticArrays, Test, Logging
using PDEStudioCore: JLD2, _reconstructed_type as rt
set_save_path!(mktempdir())
anon = Module(); Core.eval(anon, :(struct Hidden; a::Int; end))
H(i) = Base.invokelatest(anon.Hidden, i)
f = joinpath(mktempdir(), "h.jld2")
roundtrip(v) = (JLD2.jldsave(f; v = v); JLD2.load(f, "v"))
show_rt(label, v) = println(rpad(label, 64), repr(rt(v)))

println("== false positives (should all be nothing)")
for (label, v) in [
        "Dict{Symbol,Any} mixed" => Dict{Symbol, Any}(:a => 1, :b => "x", :c => [1.0], :d => Float64, :e => Any[Int, :s]),
        "nested Any vectors" => Any[Any[Any[Any[Any[1]]]]],
        "String with JLD2.ReconstructedMutable" => "JLD2.ReconstructedMutable{:X}",
        "Any[String with JLD2.UnknownType]" => Any["JLD2.UnknownType", Symbol("JLD2.Serialized")],
        "Types as values" => Any[Float64, Vector{Any}, Union{Int, Missing}, Type, DataType, Any, Union{}],
        "Vector{DataType}" => DataType[Int, Float32],
        "Vector{Union{Missing,Float64}} 10^7" => Union{Missing, Float64}[i for i in 1:10^7],
        "SVector-ish tuple" => (1, 2.0, "a"),
        "after JLD2 roundtrip: Dict{Symbol,Any}" => roundtrip(Dict{Symbol, Any}(:a => 1, :T => Float32, :v => Any[1, "a"])),
        "after JLD2 roundtrip: Any types" => roundtrip(Any[Float64, Vector{Int}, Union{Int, Nothing}]),
    ]
    show_rt(label, v)
end
println("   user module whose name ends in JLD2 (regex unanchored):")
MyJLD2 = Module(:MyJLD2); Core.eval(MyJLD2, :(struct Reconstructed; end))
show_rt("   MyJLD2.Reconstructed()", Base.invokelatest(MyJLD2.Reconstructed))

println("== true positives after a JLD2 round trip (should name Hidden)")
for (label, v) in [
        "Hidden" => H(1), "type Hidden" => anon.Hidden, "Any[1, Hidden]" => Any[1, H(2)],
        "Dict{Symbol,Any}(:h => type)" => Dict{Symbol, Any}(:h => anon.Hidden),
        "Any[Any[(1, type)]]" => Any[Any[(1, anon.Hidden)]],
        "Vector{Type}[type]" => Type[anon.Hidden],
        "depth 4: Any[Any[Any[Any[h]]]]" => Any[Any[Any[Any[H(1)]]]],
    ]
    show_rt(label, roundtrip(v))
end
println("== false negatives (reconstructed value present; nothing means missed)")
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

println("== cost")
time_rt(label, v) = (rt(v); t = @elapsed(rt(v)); a = @allocated(rt(v)); println(rpad(label, 64), round(t; sigdigits = 3), " s, ", round(a / 2^20; sigdigits = 3), " MiB"))
time_rt("Any[Float64 x 10^6]", Any[rand() for _ in 1:10^6])
time_rt("Vector{Union{Missing,Float64}} 10^7", Union{Missing, Float64}[i for i in 1:10^7])
time_rt("Any[10^3 x Any[10^3 Float64]] (10^6 leaves)", Any[Any[rand() for _ in 1:1000] for _ in 1:1000])
time_rt("Any[2000 x Any[2000 Float64]] (4*10^6 leaves)", Any[Any[rand() for _ in 1:2000] for _ in 1:2000])
time_rt("Any[30 x Any[30 x Any[30 x Any[30]]]] (8.1*10^5)", Any[Any[Any[Any[rand() for _ in 1:30] for _ in 1:30] for _ in 1:30] for _ in 1:30])
time_rt("Dict{Symbol,Any}(10^5 entries)", Dict{Symbol, Any}(Symbol("k", i) => rand() for i in 1:10^5))
time_rt("Vector{Float64} 10^8 (concrete)", zeros(10^8))

println("== cycles")
a = Any[]; push!(a, a)
println("   self-referential Any vector: ", repr(rt(a)), " (terminates)")
d = Dict{Symbol, Any}(); d[:self] = d
println("   self-referential Dict: ", repr(rt(d)))

println("== JLD2.Group")
println("   JLD2.Group <: AbstractDict: ", JLD2.Group <: AbstractDict)
JLD2.jldopen(f, "w") do file
    file["g/a"] = Any[1, 2]; file["g/b"] = 1.0
end
JLD2.jldopen(f, "r") do file
    g = file["g"]; println("   rt(group) = ", repr(rt(g)), "  typeof = ", typeof(g))
end

println("== end to end: carried-over metadata during save_sim_data(overwrite = true)")
x = collect(0.0:0.5:1.0)
p = create_param_dict(:case => "e2e")
md = Dict("top" => Dict{Symbol, Any}(:h => anon.Hidden), "nested" => Dict("run" => Dict{Symbol, Any}(:solver => anon.Hidden)),
          "vv" => [Any[H(3)]])
save_sim_data(create_sim_data(x, rand(3, 2), [0.0, 1.0], p); metadata = md, verbose = false)
logger = Test.TestLogger(min_level = Logging.Warn)
with_logger(logger) do
    save_sim_data(load_sim_data(p); overwrite = true, verbose = false)
end
for r in logger.logs
    occursin("JLD2", string(r.message)) || occursin("type", string(r.message)) && println("   WARN: ", r.message)
end
warned = [match(r"Entry '([^']+)'", string(r.message)) for r in logger.logs]
println("   warned entries: ", [m.captures[1] for m in warned if m !== nothing])
for k in ("top", "nested", "vv")
    v = JLD2.load(get_file_name(p), k)
    println("   stored $k: ", typeof(v), "  rt = ", repr(rt(v)))
end
