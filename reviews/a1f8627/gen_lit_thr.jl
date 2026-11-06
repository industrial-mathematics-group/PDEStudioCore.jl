# Threshold literals (probes/lit/, not to be committed)
d = joinpath(@__DIR__, "lit"); w(name, s) = write(joinpath(d, name), s)
for n in (3000, 4000, 5000, 7000)
    w("comma_assign_$n.txt", "x = 1, "^n * "1")
end
function levels(L, head, tail = "")
    s = "1"
    for _ in 1:L
        s = "(" * head * s * tail * ")"
    end
    return s
end
for L in (9, 10, 11, 12, 14)
    w("lvl_pow_$L.txt", levels(L, "1^"^511))
end
# mixed: commas inside each bracket level, so no level has many tokens between separators
w("lvl_comma_assign_16.txt", levels(16, "x = 1, "^300))
