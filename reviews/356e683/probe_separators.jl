# Which operators nest through `,` or `;` (the separators that reset the count): Expr depth of 50 repetitions
depth(e) = e isa Expr ? 1 + maximum(depth, e.args; init = 0) : 0
binops = ["?:", "<", "==", ".", "...", "&", "|", "∈", "=", "+=", ".=", ".+=", "//=", ">>>=", "⊻=", ":=", "~", ".~", "≔", "⩴", "≕", "->", "-->", "=>", "||", "&&",
          "<:", "where", "::", "in", "isa", "→", "←", "÷", "^", "|>", "?", "\$="]
prefix = ["\$", "&", "::", ":", "<:", "-", "!", "√", "+", "~", "..."]
res = String[]
for (sep, tag) in ((", ", "comma"), ("; ", "semicolon"), (",\n", "comma-newline"), ("\n", "newline"))
    for wrap in ("", "(", "[", "f(", "{", "T{", "Dict(")
        close = wrap == "" ? "" : wrap == "[" ? "]" : endswith(wrap, "{") ? "}" : ")"
        for op in binops
            s = wrap * ("x $op 1" * sep)^50 * "1" * close
            op == "?" && (s = wrap * ("x ? 1 : 1" * sep)^50 * "1" * close)
            d = try depth(Meta.parse(s)) catch; -1 end
            d > 10 && push!(res, "binary $(rpad(op, 6)) through $tag in $(repr(wrap * "…" * close)): depth $d")
        end
        for op in prefix
            s = wrap * ("$(op)x" * sep)^50 * "1" * close
            d = try depth(Meta.parse(s)) catch; -1 end
            d > 10 && push!(res, "prefix $(rpad(op, 6)) through $tag in $(repr(wrap * "…" * close)): depth $d")
        end
    end
end
foreach(println, res)
println(length(res), " deep cases; everything else depth ≤ 10 or a parse error")
