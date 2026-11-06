# usage: overflow_depth.jl <kind> <n> <task|main>: does str2val overflow the stack at nesting n (stderr shows the warning)
using PDEStudioCore
kind, n, where_ = ARGS[1], parse(Int, ARGS[2]), ARGS[3]
s = kind == "begin" ? "begin "^n * "1" * " end"^n :
    kind == "adjoint" ? "1" * "'"^n :
    kind == "dollar" ? "\$"^n * "1" :
    kind == "quoteparen" ? "('\"', " * "["^n * "1" * "]"^n * ")" :
    kind == "paren" ? "("^n * "1" * ")"^n : error()
str2val("1")
f() = (t = @elapsed v = str2val(s); (v isa String ? "String" : string(typeof(v))[1:min(end, 40)], t))
r = where_ == "task" ? fetch(Threads.@spawn f()) : f()
println(kind, " n=", n, " (", length(s), " chars) ", where_, " -> ", r)
