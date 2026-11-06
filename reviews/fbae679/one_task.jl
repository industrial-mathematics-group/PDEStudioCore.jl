# Parses ARGS[1] (a literal, or @file) with str2val in a fresh process; prints time, result type, max RSS,
# and with HASH=1 the time of calculate_hash on the value.
using PDEStudioCore
str2val("1"); str2val("Dict{Int, Int}()"); val2str(1); str2val("SA{Float64}[1.0]")
s = startswith(ARGS[1], "@") ? read(ARGS[1][2:end], String) : ARGS[1]
label = length(s) > 70 ? first(s, 60) * "…(" * string(length(s)) * " chars)" : s
t = @elapsed v = get(ENV, "TASK", "0") == "1" ? fetch(Threads.@spawn str2val(s)) : str2val(s)
desc = v isa String ? "String" : (v isa BigInt ? "BigInt($(ndigits(v; base = 2)) bits)" : first(string(typeof(v)), 60))
println(rpad(label, 72), " -> ", rpad(desc, 40), " str2val ", round(t; digits = 2), " s, maxrss ", round(Sys.maxrss() / 2^30; digits = 2), " GiB")
flush(stdout)
if get(ENV, "HASH", "0") == "1" && !(v isa String)
    th = @elapsed h = calculate_hash(Dict(:x => v))
    println(rpad("", 72), "    hash ", round(th; digits = 2), " s, maxrss ", round(Sys.maxrss() / 2^30; digits = 2), " GiB")
end
