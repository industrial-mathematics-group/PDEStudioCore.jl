d = joinpath(@__DIR__, "lit")
for n in (10^3, 10^4)
    e = join(fill("1", n), ", ")
    write(joinpath(d, "sa_key$n.txt"), "Dict(SA[$e] => 1)")
    write(joinpath(d, "sa_val$n.txt"), "Dict(1 => SA[$e])")
    write(joinpath(d, "sa_vec$n.txt"), "[SA[$e]]")
    write(joinpath(d, "sa_sa$n.txt"), "SA[SA[$e]]")
end
