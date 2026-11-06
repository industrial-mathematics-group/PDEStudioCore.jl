# _type_size / str2val of static array types with inconsistent, free or odd length parameters (types only, cheap).
using PDEStudioCore, StaticArrays
const TS = PDEStudioCore._type_size
for s in ["SArray{Tuple{}, Int, 0, 64}", "SArray{Tuple{0}, Int, 1, 64}", "SArray{Tuple{}, Int, 0, 1024}",
          "SArray{Tuple{}, Int, 0, 1025}", "SArray{Tuple{2}, Int, 1, 1000}", "SArray{Tuple{2}, Int, 1, -5}",
          "SArray{Tuple{2}, Int, 1, 0x40}", "SArray{Tuple{2}, Int, 1, Int32(64)}", "SArray{Tuple{2}, Int, 1, true}",
          "SArray{Tuple{0}, Int, 1, 64.0}", "SArray{Tuple{0}, Int, 1, 1.0e6}", "SArray{Tuple{0}, Int, 1, 'a'}",
          "SArray{Tuple{0}, Int, 1, :L}", "SArray{Tuple{0}, Int, 1}", "SArray{Tuple{0}, SArray{Tuple{0}, Int, 1, 64}, 1}",
          "MArray{Tuple{}, MArray{Tuple{}, Int, 0, 64}, 0, 64}", "MArray{Tuple{0}, Int, 1, 1000}",
          "SArray{Tuple{1000}, Int, 1}", "SVector{1000}", "SArray{Tuple{1, 1000}, Int, 2}",
          "Union{SArray{Tuple{}, Int, 0, 600}, SArray{Tuple{}, Int, 0, 600}}",
          "Union{SArray{Tuple{}, Int, 0, 600}, MArray{Tuple{}, Int, 0, 600}}", "Tuple{SArray{Tuple{}, Int, 0, 600}, SArray{Tuple{}, Int, 0, 600}}",
          "StaticArray{Tuple{1000}, Int, 1}", "StaticVector{1000, Int}", "SArray{Tuple{}, SArray{Tuple{}, Int, 0, 32}, 0, 32}",
          "SArray{Tuple{}, NTuple{64, Int}, 0, 64}", "SArray{Tuple{0}, Tuple{Int, Int}, 1, 512}",
          "SMatrix{2, 2, Float64, 4}", "SMatrix{2, 2, Float64, 5}", "SVector{3, Float64}", "MMatrix{32, 32, Float64, 1024}",
          "SMatrix{31, 33, Float64, 1023}", "SArray{Tuple{3, 3, 3}, Float64, 3, 27}", "SVector{1018, Float64}", "SVector{1019, Float64}"]
    v = str2val(s)
    ts = v isa Type ? TS(v) : "-"
    println(rpad(s, 68), " -> ", rpad(v isa String ? "String" : string(typeof(v)), 10), " _type_size ", ts)
end
println("--- through the types directly (not parsed)")
for T in [SArray{Tuple{0}, Int, 1, 64.0}, SArray{Tuple{0}, SArray{Tuple{0}, Int, 1, 64.0}, 1, 64.0}, SizedArray{Tuple{1000}, Int, 1, 1, Vector{Int}},
          SArray{Tuple{0}, T, 1, 2000} where T, SArray{Tuple{N}, Int, 1, 2000} where N]
    println(rpad(string(T), 68), " _type_size ", TS(T))
end
