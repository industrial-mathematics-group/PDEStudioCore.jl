# The lexer check on 10^7 random bytes (invalid UTF-8 included) and random token soup: time, allocations
using PDEStudioCore, Random
T(s) = try PDEStudioCore._too_nested(s) catch e; typeof(e) end
Random.seed!(1)
T("1")
for (name, s) in (("random ASCII", String(rand(UInt8(0x00):UInt8(0x7f), 10^7))),
                  ("token soup", join(rand(["1", "'a'", "\"s\"", "'", "\"", "\$", "(", ")", ",", ";", "#", "#=", "=#", "`", "\\", "x", " ", "\n", "::", "..."], 3 * 10^6))))
    GC.gc(); st = @timed T(s)
    println(rpad(name, 14), " ", length(s), " chars: _too_nested=", st.value, ", ", round(st.time; digits = 3), " s, ", round(st.bytes / 2^20; digits = 1), " MiB")
    GC.gc(); st = @timed str2val(s)
    println(rpad(name, 14), " str2val -> ", typeof(st.value), ", ", round(st.time; digits = 3), " s, ", round(st.bytes / 2^20; digits = 1), " MiB")
end
