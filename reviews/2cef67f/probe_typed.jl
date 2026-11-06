using PDEStudioCore, Test
const s2v = PDEStudioCore.str2val
function show1(s)
    s2v(s)  # compile
    GC.gc()
    t = @elapsed(a = @allocated(v = s2v(s)))
    println(rpad(string(length(s), " chars: ", s[1:min(end, 70)]), 84), " => ", rpad(v isa String ? "String" : string(typeof(v)), 40)[1:40],
            "  t=", round(t; digits = 3), "  alloc=", round(a / 2^20; digits = 1), " MiB")
    v
end
rep(r, k) = join(fill(r, k), ", ")
println("--- typed vectors of capped ranges: allocation grows with the number of ranges")
for k in (1, 2, 4, 8)
    show1("Vector{Float64}[" * rep("1:10^6", k) * "]")
end
for k in (1, 2, 4)
    show1("Vector{Complex{Int128}}[" * rep("1:10^6", k) * "]")
end
for k in (1, 2)
    show1("Vector{Complex{BigFloat}}[" * rep("1:10^6", k) * "]")
end
println("--- typed dicts")
for k in (1, 4)
    show1("Dict{Int, Vector{Float64}}(" * join(["$i => 1:10^6" for i in 1:k], ", ") * ")")
end
println("--- nested typed containers (each inner one is collected before any outer check)")
show1("Vector{Vector{Float64}}[" * rep("Vector{Float64}[1:10^6][1]", 1) * "]")
show1("Vector{Matrix{Float64}}[" * rep("reshape(1:10^6, (1000, 1000))", 4) * "]")
show1("Any[" * rep("Vector{Float64}[1:10^6]", 4) * "]")
show1("(" * rep("Vector{Float64}[1:10^6]", 4) * ")")
show1("[" * rep("Vector{Float64}[1:10^6]", 4) * "]")
println("--- untyped vect with promotion")
show1("[1:10^6, 1.0:2.0]")
show1("[1:10^6, [1.0]]")
show1("[" * rep("1:10^6", 4) * ", [1.0]]")
println("--- within limits: still accepted")
show1("Vector{Float64}[1:10^6]")
show1("Vector{Float64}[1:500000, 1:500000]")
