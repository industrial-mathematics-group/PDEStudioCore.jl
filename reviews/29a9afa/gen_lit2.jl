# Writes the long probe literals of this review into probes/lit/ (generated, not to be committed)
d = joinpath(@__DIR__, "lit"); mkpath(d)
w(name, s) = write(joinpath(d, name), s)
deep(n) = "["^n * "1" * "]"^n
for n in (2000, 10^4)
    w("charq_esc_$n.txt", "('\\'','\"', " * deep(n) * ")")       # '\'' misread: ',' taken as a Char, '"' opens a string
    w("triple_$n.txt", "(\"\"\" \" \"\"\", " * deep(n) * ")")     # odd quote inside a triple-quoted string
    w("interp_$n.txt", "\"\$(" * deep(n) * ")\"")                 # interpolation inside a string
    w("triplech_$n.txt", "(''','\"', " * deep(n) * ")")            # ''' (a Char in Julia) misread as adjoints
end
for n in (2000, 10^4, 10^5)
    w("powbr_$n.txt", "(1)^"^n * "1")
    w("arrowbr_$n.txt", "(a)->"^n * "1")
    w("pairbr_$n.txt", "(1)=>"^n * "1")
    w("minusbr_$n.txt", "(1)-"^n * "1")
    w("beginsc_$n.txt", "begin; "^n * "1" * "; end"^n)
    w("ifsc_$n.txt", "if true; "^n * "1" * "; end"^n)
    w("adjbr_$n.txt", "(x)'"^n)
end
# the literals of reviews/76c67a1.md (Findings 2, 3)
w("r_charquote_2000.txt", "('\"', " * deep(2000) * ")")
w("r_comment_40.txt", "1 # \"\n" * "["^40 * "1" * "]"^40)
w("r_adjoint_1e4.txt", "1" * "'"^10^4)
w("r_dollar_1e4.txt", "\$"^10^4 * "1")
w("r_begin_3000.txt", "begin "^3000 * "1" * " end"^3000)
w("r_dot_1e4.txt", "a" * ".a"^10^4)
w("r_minusnl_1e4.txt", "1-\n"^10^4 * "1")
w("r_pownl_1e4.txt", "2^\n"^10^4 * "1")
w("r_pm_1e5.txt", "±"^10^5 * "1")
w("r_arrow_1e5.txt", "1" * " → 1"^10^5)
w("r_times_1e5.txt", "1" * " × 1"^10^5)
w("r_minus1e5.txt", "-"^100_000 * "1")
w("r_paren1e5.txt", "("^100_000 * "1" * ")"^100_000)
