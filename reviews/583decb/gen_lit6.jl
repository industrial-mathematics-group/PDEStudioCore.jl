# Thresholds of the `:`-exemption families (into lit6/, generated, not to be committed)
d = joinpath(@__DIR__, "lit6"); mkpath(d)
w(name, s) = write(joinpath(d, name), s)
for n in (300, 600, 1000, 2000, 5000)
    w("kw_return_$n.txt", "x : return 1, "^n * "1"); w("kw_begin_semi_$n.txt", "x : begin 1; "^n * "1")
    w("at_sym_$n.txt", ":@a 1, "^n * "1")
end
