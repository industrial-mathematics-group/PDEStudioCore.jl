# `@` right after `:` (exempted by fbae679 together with keywords and assignments): macro calls nest through commas?
using PDEStudioCore
T = PDEStudioCore._too_nested
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
d(s) = try depth(Meta.parse(s; raise = true)) catch; -1 end
for u in ["x : @a 1", "1:@a 1", "x ? y : @a 1", ":@a 1", "x :@a 1", "1 : @a 1", ":(@a 1)", "x:(@a 1"], (sep, tag) in ((", ", ","), ("; ", ";"), ("\n", "nl")),
    (o, c) in (("", ""), ("(", ")"), ("[", "]"), ("{", "}"))
    s = o * (u * sep)^50 * "1" * c
    println(rpad(repr(u), 16), rpad(tag, 4), rpad(repr(o), 5), " T = ", rpad(T(s), 6), " depth(50) = ", d(s))
end
