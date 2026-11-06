d = joinpath(@__DIR__, "lit"); w(name, s) = write(joinpath(d, name), s)
for n in (2000, 5000, 10^4, 10^5)
    w("semi_call_$n.txt", "Dict(" * "1; "^n * "1)")
end
