# The allowlist parser against the parser it replaced (`reference_str2val.jl`): every literal parses to the same
# value as before, except the intended differences listed here. Because `val2str` writes a refused value's text
# unchanged (a top-level string), the normalised parameters hash exactly as before in every case.
include("reference_str2val.jl")

@enum DiffColor DiffRed DiffBlue
struct DiffStruct
    a::Int
    b::Float64
end

@testset "str2val against the previous parser" begin
    same(a, b) = a === b || (isequal(a, b) && typeof(a) == typeof(b))

    # 1. What val2str writes (the forms in the cache and in CSV files)
    values = Any[
        0, -1, typemax(Int), typemin(Int) + 1, Int128(2)^100, typemax(Int128), big(2)^200, -big(3)^150,
        1.5, -0.0, 1e300, 5e-324, Inf, -Inf, NaN, 2//3, -7//4, 1 + 2im, 1.5 - 2.5im, 1//2 + 3//4 * im,
        Int8(-3), UInt8(7), Int16(5), Int32(-9), UInt64(2)^63, typemax(UInt128), big(2)^70 // 3, 1.5f0, Float16(0.25),
        NaN32, Inf16, big(1.5), Complex{Float32}(1, 2), Complex{BigInt}(1, 2), true, false, π, ℯ,
        "text", "a b", "", :sym, Symbol("a b"), 'x', '"', nothing, missing,
        Float64, Float32, Int, Vector{Float64}, Matrix{Int}, Array{Int, 3}, NTuple{3, Int}, NTuple{256, Int},
        Tuple{Int, String}, Tuple{}, Dict{Symbol, Any}, Val{3}, Union{Int, Nothing}, SVector{3, Float64},
        SMatrix{2, 2, Float64, 4}, Complex{Float64}, Rational{BigInt}, Pair{Symbol, Int}, Any, Nothing, Type{Float64},
        (1, 2), (1,), (), (true, false), (1, "a", :b, 2.5), ((1, 2), (3, (4,))), (nothing, 1), (Float64, :T),
        [1, 2, 3], Float64[], Any[], [1.0, NaN], ["a", "b"], [:a, :b], [true, false], Any[1, "a", :b], [[1, 2], [3]],
        [Float32[1, 2]], Vector{Int}[[1], [2, 3]], [(1, 2), (3, 4)], [1 2; 3 4], zeros(2, 1, 3),
        reshape(Float64[], 0, 3), reshape(collect(1:24), 2, 3, 4), [[1 2; 3 4]], Matrix{Float64}[[1.0 2.0]],
        Int8[1, 2], UInt8[0xff], BigInt[1, big(2)^100], [1//2, 3//4], [1 + 2im], [ntuple(i -> 1.0, 4)],
        [ntuple(i -> i, 256)], ["a" "b"; "c" "d"], [2.0;;; 3.0], [SVector(1.0, 2.0)], [SVector{3, Int}(1, 2, 3)],
        [SMatrix{2, 2}(1.0, 2.0, 3.0, 4.0)], SVector(1.0, 2.0), SA[1, 2, 3], SMatrix{2, 2}(1, 2, 3, 4),
        MVector(1.0, 2.0), Real[1, 2.5], Union{Nothing, Int}[nothing, 1], Any[nothing, missing], [π], [""],
        Dict(:a => 1, :b => [10, 20]), Dict{String, Float64}("x" => 1.5), Dict{Symbol, Any}(), Dict(1 => (1, 2)),
        Dict(:a => Dict(:b => 1)), Dict{Tuple{Int, Int}, Symbol}((1, 2) => :x), Dict(:T => Float32),
        Val(3), Val(:x), Val(2^62), Val((1, 2)), Val(true), Val(Float64), DiffRed, DiffStruct(1, 2.0),
        (x -> x), sin, Dict(:T => Float32, :A => Vector), [sin, cos], Function,
    ]
    # 2. Typed by hand (editors, CSV files)
    typed = [
        "2π", "1/3", "1e-3", "-Inf", "-1", "+3", "1_000", "0x1f", "0b101", "1.5e300 * 10", "pi/4", "π", "ℯ",
        "sqrt(2)", "exp(1)", "log(2)", "log2(8)", "log10(100)", "sin(1)", "cos(0)", "tan(0.5)", "abs(-3)", "7 % 3",
        "2^10", "2.0^-3", "3//4", "1 + 2im", "im", "big\"123456789012345678901234567890\"", "1.5f0", "Float16(1.5)",
        "Float32(2)", "BigInt(2)^100", "Int8(3)", "UInt8(255)", "Complex(2)", "Rational(3)", "BigFloat(1.5)",
        "sqrt(big\"2\")", "exp(BigFloat(1))", "1:10", "0:0.1:1", "10:-1:1", "1:0", "-5:5", "(1:10)", "0:π/4:π",
        "1//1:10//1", "1//2:1//2:2", "1:1//2:3", "BigInt(1):BigInt(5)", "1:10^6", "1:10^6+1",
        "[1, 2, 3]", "[1.0, 2]", "(1, 2.0)", "(:a,)", ":a", "\"quoted\"", "'c'", "nothing", "missing", "true",
        "Dict(:a => 1)", "Dict{Symbol, Any}(:a => 1, :b => [1, 2])", ":a => 1", "Float32[1, 2]", "SA[1.0, 2.0]",
        "SA{Float32}[1, 2]", "SA{Float64}[1.0, 2.0]", "(SA{Float64}[1.0], 1.5f0, Float16(1.5))",
        "Any[SA{Int64}[1, 2], 0.5f0]", "SVector{2, Float64}[Float64[1.0, 2.0]]", "Vector{Float64}[[1.0], [2.0]]",
        "reshape([1, 2, 3, 4], (2, 2))", "Val{3}()", "Val{:x}()", "Symbol(\"a b\")", "<empty>", "",
        "upwind", "lax_friedrichs", "sin", "exit()", "rm(\"x\")", "run(`ls`)", "EnvDict()", "x -> x",
        "NTuple{300, Float64}", "SVector{300, Float64}", "SMatrix{17, 17, Float64, 289}",
        "Dict{Symbol, NTuple{300, Int64}}()", "Array{Float64, 16}", "Array{Float64, 17}", "Array{Float64, 300}",
        "NTuple{1024, Int}", "NTuple{1025, Int}", "NTuple{2^62, Int}", "Dims{257}",
        "Base.OneTo{Int}[10]", "UnitRange{Int64}", "StepRangeLen", "Base.EnvDict", "Date(2020)", "DataFrame",
        "ParamDict()", "IOStream", "Symbol", "Function", "DataType",
        "sqrt(1//4)", "exp(1//2)", "sin(1//2)", "log(3//2)", "sqrt(1//4 + 0im)", "sqrt(big\"1\"//3)",
        "SA_F64[1, 2]", "SA_F32[1, 2]", "IdDict(1 => 2)", "BitVector", "SubString{String}[\"a\"]", "Colon",
        "BigInt(2)^1000:BigInt(2)^1000+10", "SVector{64, SVector{8, Int}}[]",
    ]
    # 3. Every allowlisted type in common patterns
    for name in string.(keys(PDEStudioCore._LITERAL_TYPES))
        append!(typed, [name, "$name[]", "Vector{$name}", "Tuple{$name, $name}", "Dict{Symbol, $name}()",
                        "Union{Nothing, $name}"])
    end

    corpus = unique!(vcat(String[val2str(v) for v in values], typed))
    @test length(corpus) > 450

    # The intended differences (old -> new); everything else must be identical.
    widened = Set([   # values the old parser refused (they became strings): now parsed
        "NTuple{300, Float64}", "SVector{300, Float64}", "SMatrix{17, 17, Float64, 289}",
        "Dict{Symbol, NTuple{300, Int64}}()", "NTuple{1024, Int}", "1//2:1//2:2", "1:1//2:3",
    ])
    refused = Set([   # parsed by the old parser, strings now
        # transcendental functions of BigInt/BigFloat (cost grows with the size; crashed for huge exponents)
        "sqrt(big\"2\")", "exp(BigFloat(1))",
        # types outside the allowlist (not written by val2str for parameters), and arrays with more than 16 dims
        "UnitRange{Int64}", "StepRangeLen", "DataFrame", "ParamDict()", "IOStream",
        "Array{Float64, 17}",
        # names reachable through `using`, not written by val2str for parameters (IdDict: val2str cannot write it)
        "BitVector", "SubString{String}[\"a\"]", "Colon", "IdDict(1 => 2)",
    ])
    differences = String[]
    for s in corpus
        old, new = OldStr2Val.str2val(s), str2val(s)
        same(old, new) && continue
        if s in widened
            @test old isa String && !(new isa String)
        elseif s in refused
            @test !(old isa String) && new isa String
            # the hash text (top level) is unchanged, except for hand-typed texts val2str never writes: function
            # calls, the alias `ParamDict`, and types of dependencies (written module-qualified, e.g.
            # `DataFrames.DataFrame`, which no parser read back), and `IdDict` values (val2str can't write them)
            @test s in ("exp(BigFloat(1))", "ParamDict()", "DataFrame", "IdDict(1 => 2)") || val2str(new) == val2str(old)
        else
            push!(differences, s)
        end
    end
    isempty(differences) || @info "Unexpected differences" differences
    @test isempty(differences)

    # 4. Every type the old parser could reach (Core, Base, PDEStudioCore and the packages it uses, e.g.
    #    StaticArrays, Dates, DataFrames): the allowlisted ones parse to the same type, the others are strings
    #    now (e.g. `BitVector`, `SubString`, `IdDict`, whose values `val2str` can't write). None of them appears in
    #    the parameters of the downstream packages (HyperCloud uses `:T => Float64`/`Float32`).
    reachable = Set{Symbol}()
    for mod in (Core, Base, PDEStudioCore)
        for n in names(mod; all = false, imported = true, usings = true)
            isdefined(mod, n) && getglobal(mod, n) isa Type && push!(reachable, n)
        end
    end
    allowed = 0
    for n in reachable
        old, new = OldStr2Val.str2val(string(n)), str2val(string(n))
        if haskey(PDEStudioCore._LITERAL_TYPES, n)
            allowed += 1
            @test same(old, new)
        else
            @test new isa String
        end
    end
    @test allowed >= 50
    # every allowlisted name parses to its type
    @test all(((n, T),) -> str2val(string(n)) === T, PDEStudioCore._LITERAL_TYPES)
end

@testset "str2val allowlist and bounds" begin
    # nested type parameters multiply (three levels of 256 aborted the compiler, two compiled for minutes)
    @test str2val("NTuple{256, NTuple{256, Int}}") isa String
    @test str2val("Dict{NTuple{256, NTuple{256, Int}}, Int}()") isa String
    @test str2val("Dict{NTuple{256, NTuple{256, NTuple{256, Int}}}, Int}()") isa String
    @test str2val("NTuple{256, NTuple{256, NTuple{256, Any}}}[]") isa String
    @test str2val("Dict((" * join(fill("1", 10^4), ", ") * ",) => 1)") isa String   # an untyped long key
    @test str2val("Dict((1, 2) => 3)") == Dict((1, 2) => 3)
    @test str2val("Dict{Array{Int, 256}, Int}()") isa String
    @test str2val("Array{Int, 16}") == Array{Int, 16}
    # BigFloats with huge exponents (segfaulted in MPFR)
    @test str2val("BigInt(BigFloat(2)^(2^28))") isa String
    @test str2val("BigInt(BigFloat(2)^(2^36))") isa String
    @test str2val("cos(BigFloat(2)^(2^40))") isa String
    @test str2val("sin(BigFloat(2)^(2^40) + 0im)") isa String
    @test str2val("Rational{BigInt}(BigFloat(2)^(-2^36))") isa String
    @test str2val("BigInt(big\"1.5e100000000\")") isa String
    @test str2val("BigFloat(2)^100") == BigFloat(2)^100
    # integer type parameters up to 1024, the size of the whole type up to 1024 parameters
    @test str2val("NTuple{300, Float64}") == NTuple{300, Float64}
    @test str2val("SMatrix{17, 17, Float64, 289}") == SMatrix{17, 17, Float64, 289}
    @test str2val(val2str([ntuple(_ -> 1.0, 300)])) == [ntuple(_ -> 1.0, 300)]
    @test str2val("NTuple{1025, Int}") isa String
    # Rational step ranges
    @test str2val("1//2:1//2:2") == 1//2:1//2:2
    # only allowlisted types: e.g. no ENV, no lazy arrays, no types of other packages
    @test str2val("Base.EnvDict()") isa String && str2val("EnvDict()") isa String
    @test str2val("OneTo{Int}[10]") isa String
    @test str2val("Date(2020)") isa String
    # type values used downstream
    @test str2val("Float32") === Float32 && str2val("Float64") === Float64
    # static arrays: their elements count towards the size of a type (nested ones aborted Julia, also as `SA` keys
    # and with a free element type, which ran out of memory in type inference)
    @test str2val("Dict{SVector{64, SVector{64, SVector{64, Int}}}, Int}()") isa String
    @test str2val("Dict{SVector{256, SVector{256, Int}}, Int}()") isa String
    @test str2val("SVector{1000, SVector{1000, Int}}[]") isa String
    @test str2val("Pair{SVector{256, SVector{256, Int}}, Int}[]") isa String
    @test str2val("SArray{Tuple{1000, 1000, 1000}}[[1.0]]") isa String
    @test str2val("SMatrix{1000, 1000}[[1.0]]") isa String
    @test str2val("Dict(SA[" * join(fill("1", 2000), ", ") * "] => 1)") isa String
    @test str2val("SVector{300, Float64}[]") == SVector{300, Float64}[]
    @test str2val("Dict(SA[1, 2] => 1)") == Dict(SA[1, 2] => 1)
    # ... also through the length parameter of SArray/MArray, which sets the layout where it disagrees with the size
    @test str2val("Dict{SArray{Tuple{}, SArray{Tuple{}, SArray{Tuple{}, Int, 0, 64}, 0, 64}, 0, 64}, Int}()") isa String
    @test str2val("Dict{SArray{Tuple{0}, SArray{Tuple{0}, Int, 1, 256}, 1, 256}, Int}()") isa String
    @test str2val("SMatrix{2, 2, Float64, 4}") === SMatrix{2, 2, Float64, 4}
    # the text scanner (`Meta.parse` overflows its stack on deep nesting): Char literals and comments, nesting
    # without brackets, chains across lines
    T = PDEStudioCore._too_nested
    @test T("('\"', " * "["^2000 * "1" * "]"^2000 * ")") && T("1 # \"\n" * "["^40 * "1" * "]"^40)
    @test T("1" * "'"^2000) && T("\$"^2000 * "1") && T("begin "^2000 * "1" * " end"^2000) && T("a" * ".a"^2000)
    @test T("1-\n"^2000 * "1") && T("±"^2000 * "1") && T("1 → "^2000 * "1")
    # ... read with Julia's lexer: escaped and odd Chars, triple quotes, interpolation, bracketed chains, blocks
    deep = "["^2000 * "1" * "]"^2000
    @test T("('\\'','\"', $deep)") && T("(''','\"', $deep)") && T("('\\xf0\\x80\\x80\\x80','\"', $deep)")
    @test T("(\"\"\" \" \"\"\", $deep)") && T("\"\$($deep)\"")
    @test T("(1)^"^2000 * "1") && T("(a)->"^2000 * "1") && T("begin; "^20 * "1" * "; end"^20)
    @test !T("[:begin, :end, :if]") && !T("var\"#a\"") && !T(val2str(Any['\'', '"', "\$x", "a'b"]))
    @test str2val("1 # c") === 1 && str2val("[:begin, :end]") == [:begin, :end]
    @test str2val(val2str(Symbol("x" * "′"^1100))) == Symbol("x" * "′"^1100)
    # ... chains spread over bracket levels (each level below the limit), and what nests through commas
    levels(L, head, tail = "") = foldl((inner, _) -> "(" * head * inner * tail * ")", 1:L; init = "1")
    @test T(levels(16, "1^"^511)) && T(levels(31, "", "'"^1022)) && T(levels(31, "- "^1022))
    @test T("x = 1, "^2000 * "1") && T("x ~ 1, "^2000 * "1") && T("[" * "@a 1, "^2000 * "1]")
    nested = foldl((inner, _) -> "Any[" * join(fill("1", 100), ", ") * ", " * inner * "]", 1:30; init = "1")
    @test !T(nested) && str2val(nested) isa Vector{Any}
    @test !T(val2str(Any['"', "("^40])) && !T(val2str(Dict(Symbol("k", i) => -i for i in 1:5000)))
    @test str2val(val2str(Any['"', "("^40])) == Any['"', "("^40]
    @test str2val(val2str(('"', "-"^1100))) == ('"', "-"^1100)
    @test str2val(val2str(Any['\'', '\\', 'é', "a'b"])) == Any['\'', '\\', 'é', "a'b"]
    # ranges of big numbers: elements × bits bounded (hashing writes every element)
    @test str2val("BigInt(2)^524288:BigInt(2)^524288+999") isa String
    @test str2val("BigInt(1):BigInt(5)") == BigInt(1):BigInt(5)
    # nesting: of brackets (also beyond what `Meta.parse` survives) and of operator chains
    @test str2val("["^33 * "1" * "]"^33) isa String
    @test str2val("("^100_000 * "1" * ")"^100_000) isa String
    @test str2val("Dict(1 => "^40 * "1" * ")"^40) isa String
    @test str2val("1-"^2000 * "1") isa String && str2val("-"^2000 * "1") isa String
    @test str2val("["^8 * "1" * "]"^8) == [[[[[[[[1]]]]]]]]
    @test str2val("[" * join(fill("-1.5", 5000), ", ") * "]") == fill(-1.5, 5000)   # (separated: no chain)
    @test str2val("\"" * "("^100 * "\"") == "("^100                                  # (inside a string)
    # transcendental functions of Rationals (a recursion overflowed the stack), not of Rational{BigInt}
    @test str2val("sqrt(1//4)") === 0.5 && str2val("exp(1//2)") === exp(0.5)
    @test str2val("sqrt(1//4 + 0im)") === sqrt(0.25 + 0im)
    @test str2val("sqrt(big\"1\"//3)") isa String
    # IdDict is no literal (`val2str` can't write it); SA_F64/SA_F32 are
    @test str2val("IdDict(1 => 2)") isa String
    @test str2val("SA_F64[1, 2]") === SA_F64[1, 2] && str2val("SA_F32[1, 2]") === SA_F32[1, 2]
end
