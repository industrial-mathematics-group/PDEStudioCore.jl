# Quick look: _too_nested of full-size attack texts, and Expr depth of small (3-level, 20-link) versions
using PDEStudioCore
T = PDEStudioCore._too_nested
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
# comma/semicolon inside the closed group resets the outward carry: level = open * inner * chain * sep * "1" * close
lv(L, chain; open = "(", sep = ", ", close = ")") = foldl((inner, _) -> open * inner * chain * sep * "1" * close, 1:L; init = "1")
cases = [
    ("tuple, left -",      (n, L) -> lv(L, "-1"^n)),
    ("tuple, postfix '",   (n, L) -> lv(L, "'"^(2n))),
    ("tuple, ::T",         (n, L) -> lv(L, "::T"^n)),
    ("tuple, where T",     (n, L) -> lv(L, " where T"^n)),
    ("tuple, .a",          (n, L) -> lv(L, ".a"^n)),
    ("tuple, [1] index",   (n, L) -> lv(L, "[1]"^(2n))),
    ("tuple, (1) call",    (n, L) -> lv(L, "(1)"^(2n))),
    ("tuple, trailing ,",  (n, L) -> lv(L, "-1"^n; sep = ",", close = ")")),
    ("block ;",            (n, L) -> lv(L, "-1"^n; sep = "; ")),
    ("vect ,",             (n, L) -> lv(L, "-1"^n; open = "[", close = "]")),
    ("vcat ;",             (n, L) -> lv(L, "-1"^n; open = "[", sep = ";", close = "]")),
    ("braces ,",           (n, L) -> lv(L, "-1"^n; open = "{", close = "}")),
    ("call f( ;",          (n, L) -> lv(L, "-1"^n; open = "f(", sep = "; ")),
    ("curly T{ ,",         (n, L) -> lv(L, "-1"^n; open = "T{", close = "}")),
    ("tuple, left *",      (n, L) -> lv(L, "*1"^n)),
    ("tuple, left //",     (n, L) -> lv(L, "//1"^n)),
    ("tuple, |>",          (n, L) -> lv(L, "|>f"^n)),
    ("tuple, ...",         (n, L) -> lv(L, "..."^(2n))),
]
for (name, f) in cases
    full = f(511, 31)
    small = f(20, 3)
    d = try depth(Meta.parse(small)) catch e; "ERR" end
    println(rpad(name, 22), " T(full 31×511) = ", rpad(T(full), 6), " size ", rpad(sizeof(full), 8), " depth(3×20) = ", d)
end
