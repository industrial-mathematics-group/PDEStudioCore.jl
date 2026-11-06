# The candidate fix of patched.jl on every generated literal and on the val2str values of both parity probes
include(joinpath(@__DIR__, "patched.jl"))
T = PDEStudioCore._too_nested
for dir in ("lit", "lit2"), f in sort(readdir(joinpath(@__DIR__, dir)))
    s = read(joinpath(@__DIR__, dir, f), String)
    println(rpad(f, 32), " current: ", rpad(T(s), 6), " fix: ", too_nested_fix(s))
end
# quoted-operator exemption: does it let anything nest through commas?
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
for (name, f) in [("x :~ 1, ", n -> "x :~ 1, "^n * "1"), ("a ? b :~ c, ", n -> "a ? b :~ c, "^n * "1"),
                  ("x : = 1, ", n -> "x : = 1, "^n * "1"), (":(=) = 1, ", n -> ":(=) = 1, "^n * "1"),
                  (":~ = 1, ", n -> ":~ = 1, "^n * "1"), (":(= 1, ", n -> ":(= 1, "^n * "1"),
                  ("[:~ 1, ", n -> "[" * ":~ 1, "^n * "1]"), (":+= 1, ", n -> ":+= 1, "^n * "1"),
                  ("(x):~1, ", n -> "(x):~1, "^n * "1"), ("x:+=1, ", n -> "x:+=1, "^n * "1")]
    d = try depth(Meta.parse(f(50))) catch; "parse error" end
    println(rpad(repr(name), 18), " depth(50) = ", rpad(d, 12), " fix(2000) = ", too_nested_fix(f(2000)))
end
