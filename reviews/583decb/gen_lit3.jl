# New attack texts of this review (into lit3/, generated, not to be committed)
d = joinpath(@__DIR__, "lit3"); mkpath(d)
w(name, s) = write(joinpath(d, name), s)
for n in (10^4, 10^5)
    # keywords after `:` that take a comma list (exempted as in `:begin`)
    w("kw_return_$n.txt", "x : return 1, "^n * "1"); w("kw_range_return_$n.txt", "1:return 1, "^n * "1")
    w("kw_tern_return_$n.txt", "x ? y : return 1, "^n * "1"); w("kw_local_$n.txt", "1:local x, "^n * "1")
    w("kw_global_$n.txt", "x : global x, "^n * "1"); w("kw_return_vect_$n.txt", "[" * "x : return 1, "^n * "1]")
    w("kw_return_paren_$n.txt", "(" * "1:return 1, "^n * "1)")
    # blocks after `:` that are never closed (parse error, but the parser recurses first)
    w("kw_begin_semi_$n.txt", "x : begin 1; "^n * "1"); w("kw_begin_nl_$n.txt", "x : begin 1\n"^n * "1")
    w("kw_let_semi_$n.txt", "1:let; "^n * "1"); w("kw_if_semi_$n.txt", "x ? y : if 1; "^n * "1")
    w("kw_quote_semi_$n.txt", "x : quote 1; "^n * "1"); w("kw_for_semi_$n.txt", "x : for i in 1; "^n * "1")
    w("kw_func_semi_$n.txt", "x : function f(); "^n * "1"); w("kw_try_semi_$n.txt", "x : try 1; "^n * "1")
    # operator Symbols after the change: `:~` and friends between separators
    w("sym_tilde_$n.txt", "x :~ 1, "^n * "1"); w("sym_colon_tilde_$n.txt", "(:~, "^1 * ":~ 1, "^n * "1)")
    w("sym_quote_assign_$n.txt", ":(=) => 1, "^n * "1"); w("sym_tern_$n.txt", "x ? y :~ z, "^n * "1")
end
lv(L, chain; open = "(", sep = ", ", close = ")") = foldl((inner, _) -> open * inner * chain * sep * "1" * close, 1:L; init = "1")
# chain in the first element (after the closed group), and the group first in a later element
lvf(L, chain) = foldl((inner, _) -> "(1, " * inner * chain * ")", 1:L; init = "1")
for L in (8, 16, 31)
    w("first_adj_$L.txt", lvf(L, "'"^1022)); w("first_minus_$L.txt", lvf(L, "-1"^511))
    w("sep_tuple_tilde_$L.txt", lv(L, ":~"^511))       # `:~` chains (2 tokens each) after the change
    w("sep_tuple_adj2_$L.txt", lv(L, "'"^1022; sep = ", 1, 1, "))
end
