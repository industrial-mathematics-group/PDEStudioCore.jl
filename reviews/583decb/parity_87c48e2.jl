# Old (test/reference_str2val.jl) vs new str2val on forms the differential corpus does not contain.
using PDEStudioCore, StaticArrays
include(joinpath(@__DIR__, "../repo/test/reference_str2val.jl"))
same(a, b) = a === b || (isequal(a, b) && typeof(a) == typeof(b))
vals = Any[
    Dict{Symbol, DataType}(:T => Float64), [Float64, Int], Type[Float64], Dict(:T => Vector{Float64}),
    Dict{Symbol, Union{Int, Nothing}}(:a => 1), Union{Nothing, Float64}[nothing, 1.0], Union{Missing, Float64}[missing, 1.0],
    Val((1, 2)), Val(:a), Val((:a, :b)), Val{Float64}(), Val(1.5), Val('c'), [π], Irrational{:π}, Irrational,
    Complex{Rational{Int}}, Rational{Int}[1//2], ComplexF64[1 + 2im], [im], Complex{Rational{Int}}(1//2, 1//3),
    MArray{Tuple{2}, Float64, 1, 2}, MVector{2, Float64}, MMatrix{2, 2, Float64, 4}, SizedVector{3, Float64},
    SizedVector{2}([1.0, 2.0]), Size(3), Tuple{Vararg{Int}}, NTuple{3, Union{Int, Nothing}}, Tuple{Symbol, Val{:x}},
    split("a,b", ","), SubString("ab", 1, 1), [Int32(1)], Vector{Vector{Float64}}, Dict{Symbol, Any}(:a => Dict{Symbol, Any}(:b => 1)),
    BitVector([true, false]), BitVector, trues(2, 2), 1:3, 0.0:0.5:1.0, Base.OneTo(3), [1:2, 3:4], (1:2, 3.0),
    [Float32(1.5)], Float16[1, 2], Int8[1], Dict(1 => [SVector(1.0, 2.0)]), [SVector{2, Float32}(1, 2)],
    Dict(:velocities => ((-1.0,), (1.0,))), ((-1.0, 1.0), (2.0, 3.0)), [(1, :a)], [:a => 1], Pair{Symbol, Float64}[:a => 1.0],
    Set([1, 2]), (a = 1, b = 2), Colon(), Ref(1), Nothing, Missing, Union{}, Any[Float64, Int], [Vector, Matrix],
    Dict(:a => Union{Int, Nothing}), Some(1), Symbol[], Dict{String, Vector{Symbol}}("x" => [:a]),
    Array{Float64, 0}, fill(1.0), Matrix{Union{Int, Nothing}}(undef, 0, 2), [1.0 2.0], zeros(Float32, 2, 2),
    Dict{Int, Symbol}(1 => :periodic, 2 => :wall), Dict(:a => 1.5f0), (Float32, Float64), Function, sin,
    big(1.5), BigFloat(2)^100, Complex{BigFloat}(1, 2), [big(1.5)], Rational{BigInt}(1, 3), [1//3 + 0im],
]
typed = [
    "2π", "π/4", "2.0π", "sqrt(2)/2", "exp(-1)", "10^-3", "10.0^-3", "1e-3", "3e8", "-π", "2pi", "pi", "ℯ^2", "exp(1//2)",
    "sqrt(1//4)", "sin(1//2)", "log(3//2)", "sqrt(2//1 + 0im)", "abs(-1//2)", "sqrt(1//4 + 0im)", "exp(im)", "sqrt(-1 + 0im)",
    "1.0:0.1:2.0", "1:2:9", "0:0.25:1", "(0, 1)", "(0.0, 1.0)", "[0.1, 0.2]", "[1, 2.5]", "Float32(0.1)", "0.1f0",
    "Float16(0.1)", "Int32(5)", "UInt8(5)", "Inf32", "-Inf32", "NaN16", "1.0e10", "0x10", "0o17", "1_000_000",
    ":x", "Symbol(\"x\")", "nothing", "missing", "Nothing", "Missing", "Union{Missing, Float64}", "Matrix{Float64}",
    "AbstractVector{Float64}", "Dict{Symbol, Any}()", "Dict{Int64, Symbol}(1 => :periodic, 2 => :wall)",
    "SA[1.0 2.0; 3.0 4.0]", "SA{Float64}[1 2; 3 4]", "SA_F64[1, 2]", "SVector(1.0, 2.0)", "SVector{2}(1.0, 2.0)",
    "@SVector [1.0, 2.0]", "SA{Float32}[1, 2]", "MVector{2, Float64}", "Complex{Float64}", "ComplexF32", "Rational{Int64}",
    "Complex{Int64}[1 + 2im]", "Rational{Int64}[1//2]", "Irrational{:π}[π]", "[π, ℯ]", "Val{(1, 2)}()", "Val{:a}()",
    "Tuple{Vararg{Int64}}", "NTuple{3, Union{Nothing, Int64}}", "SubString{String}[\"a\", \"b\"]", "Int64[1, 2, 3]",
    "BitVector", "Base.OneTo(3)", "UnitRange{Int64}[Int64[1, 2]]", "Float64[1.0 2.0]", "[1 2; 3 4]", "[1;; 2]",
    "Bool[1, 0]", "Dict(\"a\" => 1)", "(a = 1, b = 2)", "(;a = 1)", "Some(1)", "Ref(1)", "Colon()", "Colon",
    "true", "false", "-0.0", "+1", "-(1)", "2 * 3", "1 - 2im", "(1 + 2im) * im", "1 // 0", "0 // 0", "1 / 0", "1 % 0",
    "big\"1.5\"", "big\"10\"^30", "BigFloat(\"1.5\")", "Int(2.0)", "Int64(2.0)", "Float64(1//3)", "Float64(π)", "Float32(π)",
    "Complex(1, 2)", "Rational(1, 2)", "BigInt(10)^50", "Int128(10)^30", "UInt128(1)", "Int16[1, 2]", "Float32[1.5]",
    "Vector{Float64}()", "Float64[]", "Any[]", "[]", "()", "(1,)", "[(1, 2)]", "[:a => 1]", "Pair{Symbol, Int64}[:a => 1]",
    "Union{Nothing, Int64}[nothing, 1]", "Union{Int64, Nothing}[1]", "[nothing, 1]", "[missing, 1.0]",
]
corpus = unique!(vcat(String[val2str(v) for v in vals], typed))
nd = 0; nh = 0
for s in corpus
    old, new = OldStr2Val.str2val(s), str2val(s)
    same(old, new) && continue
    global nd += 1
    hs = val2str(old) == val2str(new)
    hs || (global nh += 1)
    println(rpad(first(s, 60), 62), rpad(first(string(typeof(old)), 45), 47), " -> ", rpad(first(string(typeof(new)), 40), 42),
            hs ? "hash text same" : "HASH TEXT DIFFERS")
end
println("$(length(corpus)) literals, $nd differ, $nh with different hash text")
# Are these in the shipped differential corpus?
corp = read(joinpath(@__DIR__, "../repo/test/test_str2val_differential.jl"), String)
for s in ("sqrt(1//4)", "SizedVector", "SubString", "Size(", "IdDict")
    println(rpad(s, 14), occursin(s, corp) ? "in corpus" : "NOT in corpus")
end
# What part 4 of the differential test calls "every type the old parser could reach" misses: names from `using`
reach = Set{Symbol}()
for m in (Core, Base, PDEStudioCore), n in names(m; all = false, imported = true)
    isdefined(m, n) && getglobal(m, n) isa Type && push!(reach, n)
end
viausing = [n for n in names(StaticArrays) if isdefined(PDEStudioCore, n) && getglobal(PDEStudioCore, n) isa Type && !(n in reach)]
println("StaticArrays types reachable by the old parser but not in part 4's set: ", length(viausing), ": ", join(first(sort(viausing), 30), ", "))
for mod in (PDEStudioCore.DataFrames, PDEStudioCore.JLD2, PDEStudioCore.Dates, PDEStudioCore.LinearAlgebra, PDEStudioCore.Interpolations)
    ns = [n for n in names(mod) if isdefined(PDEStudioCore, n) && getglobal(PDEStudioCore, n) isa Type && !(n in reach)]
    println(rpad(string(mod), 30), length(ns), " more types: ", join(first(sort(ns), 12), ", "))
end
