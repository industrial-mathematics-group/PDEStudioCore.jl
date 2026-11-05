# In-process: types in an anonymous module are unknown to JLD2 when reading.
using PDEStudioCore, Test, Logging
using PDEStudioCore.JLD2
const S = PDEStudioCore
m = Module(:ForeignMod)
Core.eval(m, :(struct Note; a::Int; end))
Core.eval(m, :(mutable struct MNote; a::Int; end))
Core.eval(m, :(struct PNote{T}; a::T; end))
N(x) = Base.invokelatest(m.Note, x)
f = joinpath(mktempdir(), "x.jld2")
entries = Dict(
    "note" => N(1), "mnote" => Base.invokelatest(m.MNote, 2), "pnote" => Base.invokelatest(m.PNote{Float64}, 1.0),
    "vec" => [N(1), N(2)], "dict" => Dict("k" => N(3)), "some" => Some(N(4)), "tup" => (N(5), 1),
    "anyvec" => Any[N(6), 1], "type" => m.Note, "typevec" => Any[m.Note],
)
jldopen(io -> foreach(((k, v),) -> (io[k] = v), entries), f, "w")
loaded = with_logger(NullLogger()) do
    Dict(k => JLD2.load(f, k) for k in keys(entries))
end
@testset "nested reconstruction is detected" begin
    for k in sort(collect(keys(entries)))
        v = loaded[k]
        println(rpad(k, 8), " detected=", rpad(S._is_reconstructed(v), 6), " ", v isa Type ? "(type value) $v" : typeof(v))
    end
    for k in ("note", "mnote", "pnote", "vec", "dict", "some", "tup")
        @test S._is_reconstructed(loaded[k])
    end
end
@testset "no false positives on ordinary values" begin
    g = joinpath(mktempdir(), "y.jld2")
    ordinary = Dict("d" => Dict{String, Any}("a" => 1, "b" => [1.0, 2.0], "c" => Dict(:x => (1, "s"))),
                    "v" => rand(3, 2), "s" => "JLD2.ReconstructedStatic", "sym" => Symbol("JLD2.SerializedDict"),
                    "r" => 1:10, "t" => (1, :a, "b"), "n" => nothing, "type" => Float64, "ref" => Ref(1),
                    "mem" => Memory{Int}(undef, 2), "mref" => memoryref(Memory{Int}(undef, 3), 2))
    jldopen(io -> foreach(((k, v),) -> (io[k] = v), ordinary), g, "w")
    for (k, v) in ordinary
        w = JLD2.load(g, k)
        println(rpad(k, 6), " -> ", typeof(w), "  detected=", S._is_reconstructed(w))
        @test !S._is_reconstructed(w)
    end
    # a user type whose *value* contains the string only (not the type) must not match
    @test !S._is_reconstructed(Val{Symbol("JLD2.Reconstructed")})  # type value: DataType
end
@testset "warning through _copy_entry! for nested values" begin
    dst = joinpath(mktempdir(), "z.jld2")
    logs = Test.collect_test_logs() do
        jldopen(f, "r") do src
            jldopen(dst, "w") do d
                for k in ("vec", "dict", "anyvec", "type")
                    S._copy_entry!(d, src, k)
                end
            end
        end
    end[1]
    msgs = [string(l.message) for l in logs if l._module === S]
    println("PDEStudioCore warnings: ", msgs)
    @test any(occursin("'vec'", s) for s in msgs)
    @test any(occursin("'dict'", s) for s in msgs)
end
println("cost of _is_reconstructed on a 10^6-element Vector{Float64}: ",
        (x = rand(10^6); S._is_reconstructed(x); @elapsed S._is_reconstructed(x)), " s")
