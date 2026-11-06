# Mismatched closers: the lexer-based stack pops at any closer; how deep does the parser get?
using PDEStudioCore
T = PDEStudioCore._too_nested
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
for s in ["(]"^5 * "1", "[)"^5 * "1", "(}"^5 * "1", "{)"^5 * "1", "f(]"^5 * "1", "(1]"^5, "(1-1]"^5, ")"^3 * "1-1", "1)" * "-1"^3]
    e = try Meta.parse(s; raise = false) catch err; err end
    println(rpad(repr(s), 24), " T = ", rpad(T(s), 6), " depth ", e isa Expr ? depth(e) : "-", "  ", first(string(e), 120))
end
