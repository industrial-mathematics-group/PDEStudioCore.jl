# Keywords right after `:` (also with whitespace) or `:(`: do they pass _too_nested and nest through separators?
# Expr depth of 50 repetitions (Meta.parse at a safe size); a parse error counts as -1.
using PDEStudioCore
T = PDEStudioCore._too_nested
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
d(s) = try depth(Meta.parse(s; raise = true)) catch; -1 end
kws = ["return 1", "return", "begin 1", "quote 1", "let", "let x", "if 1", "if true 1", "for i in 1", "while 1", "try 1",
       "function f", "function", "do", "struct S", "global x", "local x", "const x", "import A", "using A", "export a",
       "break", "continue", "where", "macro m", "module M", "baremodule M", "abstract type A", "mutable struct S", "else",
       "elseif", "end", "in", "isa", "outer", "public a", "catch", "finally"]
pres = [":", ": ", "x : ", "x ? y : ", "1:", ":(", "x ? y :(", "1 : "]
res = []
for kw in kws, p in pres, (sep, tag) in ((", ", ","), ("; ", ";"), ("\n", "nl"), (" ", "sp")), (o, c) in (("", ""), ("(", ")"), ("[", "]"), ("{", "}"))
    s = o * (p * kw * sep)^50 * "1" * c
    t = T(s); dd = d(s)
    !t && dd > 10 && push!(res, (p * kw, tag, o, dd))
end
for r in res; println(r); end
println(length(res), " deep and not rejected")
