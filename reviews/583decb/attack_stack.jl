# Systematic attack on the quoting rule of 583decb, by parser recursion: the grid of attack_quote2.jl at 2000
# repetitions; every text that passes `_too_nested` is parsed with the JuliaSyntax parser (parse!, no flisp fallback)
# in a Task with a 1 MB stack (a quarter or less of a default stack); an overflow there is reported.
# Usage: julia --project=<env> attack_stack.jl <out> [n]
using PDEStudioCore
const T = PDEStudioCore._too_nested
const JS = Base.JuliaSyntax
function overflows(s; stack = 1024 * 1024)
    t = Task(() -> (JS.parse!(JS.ParseStream(s); rule = :statement); nothing), stack)
    schedule(t)
    try
        wait(t); return false
    catch e
        return e isa TaskFailedException && t.result isa StackOverflowError
    end
end
kws = ["return", "begin", "quote", "let", "if", "for", "while", "try", "function", "do", "struct", "global", "local",
       "const", "import", "using", "export", "public", "break", "continue", "macro", "module", "baremodule",
       "abstract", "primitive", "mutable", "type", "else", "elseif", "end", "catch", "finally", "outer", "as", "doc"]
ops = ["=", "~", "+=", "-=", "*=", "/=", "^=", "÷=", "%=", "|=", "&=", "⊻=", "<<=", ">>=", ">>>=", "\\=", "//=",
       ":=", "≔", "⩴", "≕", "\$="]
payloads = vcat(kws, ops, ["." * o for o in ops[1:6]], ["@a"])
forms = [":", ":(", ":.", ":(.", ":.(", "::", ":::", ":(:", "::(", ":.:", ": :", ":( ", ":. ", ":\n", ":#=c=#",
         ":((", ": (", ":(\n", ":[", ":{", "(:", "[:", "{:", "=>:", "1=>:", "x=>:", "x => :", "x=> :(", "x=>:."]
args = ["", " 1", " x", " 1, 1", "(1)", " 1;", " 1\n", " x in 1", "()"]
seps = [", ", "; ", ",", ";", "\n", " ", ",\n", "#=c=#, ", ";;", "\n\n"]
ctxs = [("", ""), ("(", ""), ("(", ")"), ("[", "]"), ("{", "}"), ("f(", ")"), ("T{", "}"), ("Dict(", ")"),
        ("[1 ", "]"), ("(1, ", ")"), ("f(; ", ")"), ("x[", "]"), ("[", ""), ("\"\$(", ")\"")]
out = open(ARGS[1], "w")
n = length(ARGS) > 1 ? parse(Int, ARGS[2]) : 2000
total = passed = over = 0
for p in payloads, f in forms, a in args, sep in seps, (o, c) in ctxs
    global total, passed, over
    s = o * (f * p * a * sep)^n * "1" * c
    total += 1
    T(s) && continue
    passed += 1
    if overflows(s)
        over += 1
        println(out, "OVERFLOW ", repr(f * p * a), " sep=", repr(sep), " ctx=", repr(o)); flush(out)
    end
end
println(out, "$total texts at n = $n, $passed pass _too_nested, $over overflow a 1 MB stack")
close(out)
