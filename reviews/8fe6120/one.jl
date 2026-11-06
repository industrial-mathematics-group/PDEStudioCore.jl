# Parses ARGS[1] (a literal) with str2val in a fresh process; prints time, result type, max RSS, and (optionally) the hash time.
using PDEStudioCore
str2val("1"); str2val("Dict{Int, Int}()"); val2str(1)
s = startswith(ARGS[1], "@") ? read(ARGS[1][2:end], String) : ARGS[1]
label = length(s) > 70 ? s[1:60] * "…(" * string(length(s)) * " chars)" : s
t = @elapsed v = str2val(s)
desc = v isa String ? "String" : (v isa BigInt ? "BigInt($(ndigits(v; base = 2)) bits)" : string(typeof(v))[1:min(end, 60)])
println(rpad(label, 72), " -> ", rpad(desc, 40), " str2val ", round(t; digits = 2), " s, maxrss ", round(Sys.maxrss() / 2^30; digits = 2), " GiB")
flush(stdout)
if get(ENV, "HASH", "0") == "1" && !(v isa String)
    th = @elapsed h = calculate_hash(Dict(:x => v))
    println(rpad("", 72), "    hash ", round(th; digits = 2), " s, maxrss ", round(Sys.maxrss() / 2^30; digits = 2), " GiB")
end
