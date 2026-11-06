# Pure scanner checks (no Meta.parse of deep texts): _too_nested and _char_literal_end on attack texts.
using PDEStudioCore
const T = PDEStudioCore._too_nested
const C = PDEStudioCore._char_literal_end
show_(label, s) = println(rpad(label, 50), " too_nested=", T(s), "  (", length(s), " chars)")
n = 2000; deep = "["^n * "1" * "]"^n
println("--- Char literal end vs Julia tokenizer")
for s in ["'\\''", "'\\\\'", "'é'", "'\\U0010ffff'", "'\\xf4\\x90\\x80\\x80'", "'\\xc3\\xa9'", "'ab'", "''", "'''", "'\"'", "'\\\"'", "'\\101'", "'a", "'"]
    j = C(s, 1)
    jl = try; v = Meta.parse(s); string(typeof(v), " ", repr(v)); catch e; "error"; end
    println(rpad(repr(s), 26), " scanner end=", rpad(repr(j), 10), " lastindex=", lastindex(s), "  Meta.parse: ", first(jl, 50))
end
println("--- bypasses (Julia parses deep nesting the scanner does not see)")
show_("('\\'','\"', deep)", "('\\'','\"', " * deep * ")")
show_("('\\'','\"',deep) val2str-like spacing", "('\\'', '\"', " * deep * ")")
show_("\"\"\" \" \"\"\", deep  (triple-quoted, odd quote)", "(\"\"\" \" \"\"\", " * deep * ")")
show_("\"\$(deep)\"  (interpolation)", "\"\$(" * deep * ")\"")
show_("\"\$(\"\$(…)\")\" nested interpolation x2000", "\"\$("^n * "1" * ")\""^n)
show_("(1)^ x2000", "(1)^"^n * "1")
show_("(1)^ x20000", "(1)^"^20000 * "1")
show_("(a)-> x20000", "(a)->"^20000 * "1")
show_("(1)=> x20000", "(1)=>"^20000 * "1")
show_("(1)- x100000", "(1)-"^100000 * "1")
show_("begin; x20000", "begin; "^20000 * "1" * "; end"^20000)
show_("let; x20000", "let; "^20000 * "1" * "; end"^20000)
show_("if true; x20000", "if true; "^20000 * "1" * "; end"^20000)
show_("(x)' x20000", "(x)'"^20000)
show_("[1]' alternating", "[1]'"^20000)
show_("-(1) chain: -(-(…)) brackets", "-("^2000 * "1" * ")"^2000)
show_("1-\\n x2000 (tested)", "1-\n"^2000 * "1")
show_("x₁ subscripts 2000 (one identifier)", "x" * "₁"^2000)
println("--- false rejections of val2str output")
for v in Any[Any['\'', '"', "a'b"], ('\'', "x"), Dict('\'' => '"'), [Symbol("x", "₁"^1100)], Symbol("α′"^600),
             "a"^5000, Any[:a => 1], ntuple(i -> Symbol("k", i), 2000), Any["\$(" * deep * ")"], [big"1.5"^1000],
             1//3 + 2im, Complex{Rational{Int}}(1//3, 2//5), reshape(collect(1.0:6.0), 2, 3), Symbol("x̂"^1100)]
    s = val2str(v)
    println(rpad(first(repr(v), 48), 50), " too_nested=", T(s))
end
