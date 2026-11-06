# Invalid UTF-8 texts: does the lexer throw inside _too_nested, and what do str2val and the reference return?
using PDEStudioCore
include(ARGS[1])  # test/reference_str2val.jl
for s in ["x\xc0\x8f", "\xc0\x8f", "[1, x\xc0\x8f]", "'\xc0\x8f'", "\"a\xc0\x8f\"", "[\"a\xc0\x8f\", 1]", "\xff", "1\xff", "x\xff"]
    t = try PDEStudioCore._too_nested(s) catch e; "throws " * string(typeof(e)) end
    new = try str2val(s) catch e; "throws " * string(typeof(e)) end
    old = try OldStr2Val.str2val(s) catch e; "throws " * string(typeof(e)) end
    println(rpad(repr(s), 22), " _too_nested: ", rpad(string(t), 34), " new: ", rpad(repr(new), 22), " old: ", rpad(repr(old), 22),
            isequal(new, old) && typeof(new) == typeof(old) ? "" : "DIFF")
end
