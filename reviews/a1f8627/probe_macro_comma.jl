# Macro calls without brackets nest through commas too? Expr depth of 50 repetitions
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
for s in ["@a 1, "^50 * "1", "@a "^50 * "1", "x = @a 1, "^50 * "1", "a -> 1, "^50 * "1", "1 => 2, "^50 * "1"]
    d = try depth(Meta.parse(s)) catch e; "error" end
    println(rpad(repr(first(s, 24)), 30), " depth ", d)
end
println("-- inside brackets")
for s in ["(" * "@a 1, "^50 * "1)", "[" * "@a 1, "^50 * "1]", "f(" * "@a 1, "^50 * "1)", "(" * "x = 1, "^50 * "1)", "[" * "x = 1, "^50 * "1]"]
    d = try depth(Meta.parse(s)) catch e; "error" end
    println(rpad(repr(first(s, 24)), 30), " depth ", d)
end
