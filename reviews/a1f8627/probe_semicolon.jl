# Bracket forms in which repeated `;` nests the Expr (`f(1; 2; 3)` puts `parameters` in `parameters`)
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
for (o, c) in (("f(", ")"), ("(", ")"), ("[", "]"), ("a[", "]"), ("T{", "}"), ("{", "}"), ("f.(", ")"), ("(1,", ")"),
               ("Dict(", ")"), ("SA[", "]"), ("Int[", "]"))
    s = o * "1; "^50 * "1" * c
    d = try depth(Meta.parse(s)) catch; -1 end
    println(rpad(repr(o * "1; 1; …" * c), 24), " depth ", d)
end
println(Meta.parse("f(1; 2; 3)") |> Meta.show_sexpr)
