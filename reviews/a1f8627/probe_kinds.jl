# Which words the lexer reports as keywords; parse shapes of comma/assignment texts; _too_nested on samples.
using PDEStudioCore
const JS = Base.JuliaSyntax
T(s) = PDEStudioCore._too_nested(s)
kinds(s) = [string(JS.kind(t)) for t in JS.Tokenize.tokenize(s)]
words = ["true", "false", "nothing", "missing", "in", "isa", "where", "var", "abstract", "mutable", "primitive", "type",
         "outer", "as", "doc", "public", "begin", "end", "do", "let", "local", "global", "const", "struct", "module",
         "baremodule", "quote", "return", "break", "continue", "macro", "function", "import", "using", "export", "try",
         "catch", "finally", "else", "elseif", "for", "while", "if", "Inf", "NaN", "π", "im"]
for w in words
    k = JS.kind(first(JS.Tokenize.tokenize(w)))
    println(rpad(w, 12), rpad(string(k), 14), " is_keyword=", JS.is_keyword(k), "  T(\"[$w]\")=", T("[$w]"), "  str2val(\"[$w]\") isa String: ", str2val("[$w]") isa String)
end
for s in ["a = b, c = d", "a -> b, c -> d", "a ? b : c, d", "a += b, c += d", "a := b, c := d", "a ~ b, c ~ d",
          "a where b, c where d", "a => b, c => d", "1:begin 2 :end", "x[:end]", ";;", "[1;;2]", "1 ; 2"]
    e = try Meta.parse(s) catch err; "ERR: " * sprint(showerror, err)[1:min(end, 80)] end
    println(rpad(repr(s), 22), " -> ", e isa Expr ? sprint(Meta.show_sexpr, e) : e, "   kinds=", kinds(s))
end
