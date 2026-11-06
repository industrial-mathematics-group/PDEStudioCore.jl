# Quote-position `:` (after `(`, `[`, `{`, `,`, `;`, `=>`) inside an open ternary: does the parser take it as the
# ternary's `:` (then the keyword after it is a real keyword)? Parse of small texts, then parser recursion at 2000
# repetitions in a 1 MB Task for those that pass `_too_nested`.
using PDEStudioCore
const T = PDEStudioCore._too_nested
const JS = Base.JuliaSyntax
function overflows(s; stack = 1024 * 1024)
    t = Task(() -> (JS.parse!(JS.ParseStream(s); rule = :statement); nothing), stack)
    schedule(t)
    try wait(t); return false catch e; return e isa TaskFailedException && t.result isa StackOverflowError end
end
for s in ["c ? a =>:b", "c ? a =>:return 1", "c ? a,:return 1", "c ? a;:return 1", "(c ? a;:return 1)", "[c ? a;:return 1]",
          "c ? (:return", "c ? [:return 1]", "c ?(:begin)", "c ? a =>:(=) 1"]
    println(rpad(repr(s), 26), " T=", rpad(T(s), 6), " ", first(repr(Meta.parse(s; raise = false)), 120))
end
units = ["c ? a =>:return 1", "c ? a,:return 1", "c ? a;:return 1", "c ? a =>:begin 1", "c ? a;:begin 1", "c ?(:return 1",
         "c ? a =>:local x", "c ? a, :return 1", "c ? a =>:~ 1", "c ? a =>:= 1", "c ? a =>:.= 1", "c ? a,:.return 1"]
for u in units, sep in (", ", "; ", "\n", " "), (o, cl) in (("", ""), ("(", ")"), ("[", "]"), ("f(", ")"))
    s = o * (u * sep)^2000 * "1" * cl
    T(s) && continue
    println("PASS T: ", rpad(repr(u * sep), 28), rpad(repr(o), 5), " overflow(1 MB)=", overflows(s))
end
println("done")
