# `:.` followed by a keyword (exempted by the `:.` rule): what the parser makes of it, and whether it recurses
using PDEStudioCore
const T = PDEStudioCore._too_nested
const JS = Base.JuliaSyntax
function overflows(s; stack = 1024 * 1024)
    t = Task(() -> (JS.parse!(JS.ParseStream(s); rule = :statement); nothing), stack)
    schedule(t)
    try wait(t); return false catch e; return e isa TaskFailedException && t.result isa StackOverflowError end
end
for s0 in ["[:.begin 1]", "(:.begin 1)", "[:.return 1, 2]", "(:.return 1, 2)", "f(:.return 1, 2)", "[:.=1]", "(:.= 1, 2)",
           "[:.begin 1; :.begin 1; 1]", "(:.let x; :.let x; 1)", "[:.begin\n1]"]
    println(rpad(repr(s0), 30), " T=", rpad(T(s0), 6), " ", repr(Meta.parse(s0; raise = false))[1:min(end, 150)])
end
for (o, u, sep, c) in [("[", ":.begin 1", "; ", "]"), ("(", ":.begin 1", "; ", ")"), ("[", ":.return 1", ", ", "]"),
                       ("(", ":.return 1", ", ", ")"), ("", ":.return 1", ", ", ""), ("[", ":.let x", "; ", "]"),
                       ("[", ":.begin 1", "\n", "]"), ("{", ":.begin 1", "; ", "}")]
    s = o * (u * sep)^2000 * "1" * c
    println(rpad(repr(o * u * sep), 24), " T(2000)=", rpad(T(s), 6), " overflow(1 MB)=", overflows(s))
end
