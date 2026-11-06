# (Variant of attack_quote.jl: depth growth > 5, the known `;`-parameters family excluded)
# Systematic attack on the quoting rule of 583decb: payload (keyword, assignment operator, dotted operator, `@`)
# × colon form × argument × separator × bracket context. Flags texts that pass `_too_nested` at 50 repetitions and
# whose Expr depth grows with the repetitions (depth(100) - depth(50) > 20), then reports T at 2000 repetitions.
# Also flags parse times above 0.2 s at 100 repetitions. Usage: julia --project=<env> attack_quote.jl [out]
using PDEStudioCore
T = PDEStudioCore._too_nested
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
d(s) = try depth(Meta.parse(s; raise = false)) catch; -1 end
kws = ["return", "begin", "quote", "let", "if", "for", "while", "try", "function", "do", "struct", "global", "local",
       "const", "import", "using", "export", "public", "break", "continue", "macro", "module", "baremodule",
       "abstract", "primitive", "mutable", "type", "else", "elseif", "end", "catch", "finally", "outer", "as", "doc"]
ops = ["=", "~", "+=", "-=", "*=", "/=", "^=", "÷=", "%=", "|=", "&=", "⊻=", "<<=", ">>=", ">>>=", "\\=", "//=",
       ":=", "≔", "⩴", "≕", "\$="]
payloads = vcat(kws, ops, ["." * o for o in ops[1:6]], ["@a"])
# colon forms in prefix position (the separator or bracket before the unit is the prefix)
forms = [":", ":(", ":.", ":(.", ":.(", "::", ":::", ":(:", "::(", ":.:", ": :", ":( ", ":. ", ":\n", ":#=c=#",
         ":((", ": (", ":(\n", ":[", ":{", "(:", "[:", "{:", "=>:", "1=>:", "x=>:", "x => :", "x=> :(", "x=>:."]
args = ["", " 1", " x", " 1, 1", "(1)", " 1;"]
seps = [", ", "; ", ",", ";", "\n", " ", ",\n", "#=c=#, ", ";;"]
ctxs = [("", ""), ("(", ")"), ("[", "]"), ("{", "}"), ("f(", ")"), ("T{", "}"), ("Dict(", ")"), ("[1 ", "]"),
        ("(1, ", ")"), ("f(; ", ")"), ("x[", "]")]
out = isempty(ARGS) ? stdout : open(ARGS[1], "w")
flagged = 0; slow = 0; total = 0; passed = 0
for p in payloads, f in forms, a in args, sep in seps, (o, c) in ctxs
    global flagged, slow, total, passed
    u = f * p * a
    s50 = o * (u * sep)^50 * "1" * c
    total += 1
    T(s50) && continue
    passed += 1
    d50 = d(s50)
    s100 = o * (u * sep)^100 * "1" * c
    t = @elapsed d100 = d(s100)
    if t > 0.2
        slow += 1
        println(out, "SLOW ", repr(u), " sep=", repr(sep), " ctx=", repr(o), " t100=", round(t; digits = 3))
    end
    if d100 - d50 > 5 && !(occursin(";", sep) && o in ("f(", "T{", "Dict(", "(1, ", "f(; "))
        s2000 = o * (u * sep)^2000 * "1" * c
        flagged += 1
        println(out, "DEEP ", repr(u), " sep=", repr(sep), " ctx=", repr(o), " d50=", d50, " d100=", d100,
                " T2000=", T(s2000))
    end
end
println(out, "$total texts, $passed pass T at 50, $flagged grow in depth, $slow slow")
out === stdout || close(out)
