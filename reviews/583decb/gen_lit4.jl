# Macro calls after `:` (exempted by fbae679): into lit4/, generated, not to be committed
d = joinpath(@__DIR__, "lit4"); mkpath(d)
w(name, s) = write(joinpath(d, name), s)
for n in (10^3, 10^4, 10^5)
    w("at_sym_$n.txt", ":@a 1, "^n * "1"); w("at_range_$n.txt", "1:@a 1, "^n * "1")
    w("at_tern_$n.txt", "x ? y : @a 1, "^n * "1"); w("at_vect_$n.txt", "[" * ":@a 1, "^n * "1]")
end
