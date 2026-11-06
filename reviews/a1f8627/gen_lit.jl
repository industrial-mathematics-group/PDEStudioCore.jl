# Writes the long probe literals of this review into probes/lit/ (generated, not to be committed)
d = joinpath(@__DIR__, "lit"); mkpath(d)
w(name, s) = write(joinpath(d, name), s)
deep(n) = "["^n * "1" * "]"^n
# --- the bypass texts of reviews/29a9afa.md (Findings 1, 2) ---
for n in (2000, 10^4)
    w("old_charq_esc_$n.txt", "('\\'','\"', " * deep(n) * ")")
    w("old_triple_$n.txt", "(\"\"\" \" \"\"\", " * deep(n) * ")")
    w("old_interp_$n.txt", "\"\$(" * deep(n) * ")\"")
    w("old_triplech_$n.txt", "(''','\"', " * deep(n) * ")")
    w("old_xesc_$n.txt", "('\\xf0\\x80\\x80\\x80','\"', " * deep(n) * ")")
end
for n in (2000, 10^4, 10^5)
    w("old_powbr_$n.txt", "(1)^"^n * "1")
    w("old_arrowbr_$n.txt", "(a)->"^n * "1")
    w("old_pairbr_$n.txt", "(1)=>"^n * "1")
    w("old_minusbr_$n.txt", "(1)-"^n * "1")
    w("old_beginsc_$n.txt", "begin; "^n * "1" * "; end"^n)
    w("old_ifsc_$n.txt", "if true; "^n * "1" * "; end"^n)
    w("old_adjbr_$n.txt", "(x)'"^n)
end
# --- new: nesting through commas (assignment binds looser than `,`: `a = b, c = d` is `a = ((b, c) = d)`) ---
for n in (2000, 10^4, 10^5)
    w("comma_assign_$n.txt", "x = 1, "^n * "1")
    w("comma_opassign_$n.txt", "x += 1, "^n * "1")
    w("comma_tilde_$n.txt", "x ~ 1, "^n * "1")
    w("comma_colonassign_$n.txt", "x := 1, "^n * "1")
end
# --- new: chains carried across bracket levels (a bracketed part is one token of its level) ---
# level = "(" * 1023 tokens of a chain * inner * ")", nested `L` levels (≤ 32 brackets)
function levels(L, head, tail = "")
    s = "1"
    for _ in 1:L
        s = "(" * head * s * tail * ")"
    end
    return s
end
for L in (8, 16, 31)
    w("lvl_pow_$L.txt", levels(L, "1^"^511))                 # right-assoc ^, 511 per level
    w("lvl_arrow_$L.txt", levels(L, "a->"^511))              # right-assoc ->
    w("lvl_pair_$L.txt", levels(L, "1=>"^511))               # right-assoc =>
    w("lvl_unary_$L.txt", levels(L, "-"^1022))               # prefix -
    w("lvl_minus_$L.txt", levels(L, "", "-1"^511))           # left-assoc - (builds a deep Expr)
    w("lvl_adj_$L.txt", levels(L, "", "'"^1022))             # postfix '
end
# --- new: unmatched closers reset the count at the top level ---
for n in (10, 20, 100)
    w("unmatched_pow_$n.txt", ("1^"^1000 * "1)")^n)
end
# --- lexer on long input ---
w("lex_str_1e7.txt", "\"" * "a"^10^7 * "\"")
w("lex_comment_1e7.txt", "1 #= " * "#= "^(10^6) * "=# "^(10^6) * "=#")
w("lex_interp_1e6.txt", "\"\$(\""^(10^6))
w("lex_ops_1e7.txt", "+"^10^7)
w("lex_commas_1e7.txt", "["* ","^10^7 * "]")
w("lex_mix_1e7.txt", ("1, " * "'a', " * "\"b\", ")^(10^6))
for n in (10, 20, 100)
    w("unmatched_pow_$n.txt", ("1^"^511 * "1)")^n)
end
