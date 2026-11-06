# Which texts with an assignment/keyword token right after `:` or `:(` pass _too_nested and still nest (Expr depth of
# 50 repetitions, Meta.parse at a safe size).
using PDEStudioCore
T = PDEStudioCore._too_nested
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
d(s) = try depth(Meta.parse(s; raise = true)) catch; -1 end
ops = ["=", "~", "+=", "-=", "*=", "^=", ":=", "≔", "⩴", "≕", ".=", ".~", "\$=", "|=", "=>", "->"]
units = String[]
for op in ops
    append!(units, [": $op 1", ":$op 1", "(:) $op 1", "x : $op 1", "x :$op 1", "1:$op 1", "x ? y :$op 1", "x ? y : $op 1",
                    ":($op 1)", ":($op) $op 1", ":($op 1", "x:($op 1)", ":$op", ":( $op )", "a[:$op 1]", ": $op x $op 1",
                    "x? y :$op z", "x ?y :$op z", ":\n$op 1", ":#= c =#$op 1", "x[: $op 1"])
end
res = []
for u in units, (sep, tag) in ((", ", ","), ("; ", ";"), ("\n", "nl")), (o, c) in (("", ""), ("(", ")"), ("[", "]"), ("f(", ")"), ("{", "}"), ("T{", "}"))
    s = o * (u * sep)^50 * "1" * c
    t = T(s); dd = d(s)
    !t && dd > 10 && push!(res, (u, tag, o, dd))
end
for r in res; println(r); end
println(length(res), " deep and not rejected")
