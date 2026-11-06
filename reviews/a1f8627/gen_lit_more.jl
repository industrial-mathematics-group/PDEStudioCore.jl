# More operator families carried across bracket levels (probes/lit/, not to be committed)
d = joinpath(@__DIR__, "lit"); w(name, s) = write(joinpath(d, name), s)
function levels(L, head, tail = "")
    s = "1"
    for _ in 1:L
        s = "(" * head * s * tail * ")"
    end
    return s
end
w("lvl_unarysp_31.txt", levels(31, "- "^1022))
w("lvl_not_31.txt", levels(31, "!"^1022))
w("lvl_sqrt_31.txt", levels(31, "√"^1022))
w("lvl_where_31.txt", levels(31, "", " where T"^511))
w("lvl_decl_31.txt", levels(31, "", "::T"^511))
w("lvl_splat_31.txt", levels(31, "", "..."^1022))
w("lvl_juxt_31.txt", levels(31, "", "x"^0 * " .+ 1"^511))
