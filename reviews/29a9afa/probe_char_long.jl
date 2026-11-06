# Invalid Chars whose repr has 4 \x escapes (longer than the 11 characters _char_literal_end looks ahead)
using PDEStudioCore
include(ARGS[1])
const T = PDEStudioCore._too_nested
for u in (0xf0808080, 0xf4908080, 0xf7bfbfbf)
    c = reinterpret(Char, u)
    for v in Any[c, [c, '"'], (c, "x")]
        s = val2str(v)
        new, old = str2val(s), OldStr2Val.str2val(s)
        println(rpad(s, 34), " char_literal_end(s,", findfirst('\'', s), ")=", repr(PDEStudioCore._char_literal_end(s, findfirst('\'', s))),
                "  too_nested=", T(s), "  new: ", typeof(new), "  old: ", typeof(old), "  equal: ", isequal(new, old))
    end
end
deep = "["^2000 * "1" * "]"^2000
println("typed: ('\\xf0\\x80\\x80\\x80','\"', deep) too_nested = ", T("('\\xf0\\x80\\x80\\x80','\"', " * deep * ")"))
