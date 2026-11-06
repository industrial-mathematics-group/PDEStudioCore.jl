# Minor items of reviews/76c67a1.md and the scanner's handling of a few typed texts, against the reference parser
using PDEStudioCore
include(ARGS[1])
for s in ["\"\"\"a\"" * "("^40 * "\"\"\"", "\"\"\"a\"b\"\"\"", "'\"'", "('\"', 1)", "\"a#b\"", "1 # c", "1 #= c =#",
          "x'", "[1, 2]'", "1'", "'", "a'", "'a'", "'''", "('\\'','\"')", "\"\$x\"", "\"\$(1 + 1)\"", "raw\"a\\\\\"",
          "1e5", "0x1f", "2π", "1.5f0", "2im", "1.e5", "a.b", "Float64[1.5, -2.0]", "\$x", "√2", "2 × 3", "1 ± 2",
          "begin 1 end", "let x = 1; x end", ":a!", "x!", "-1.5e-5 - 2.5e-5im"]
    new = str2val(s); old = OldStr2Val.str2val(s)
    println(rpad(repr(first(s, 40)), 46), " too_nested=", rpad(PDEStudioCore._too_nested(strip(s)), 6), " new: ", rpad(first(repr(new), 26), 28),
            " old: ", rpad(first(repr(old), 26), 28), isequal(new, old) && typeof(new) == typeof(old) ? "" : "DIFF")
end
