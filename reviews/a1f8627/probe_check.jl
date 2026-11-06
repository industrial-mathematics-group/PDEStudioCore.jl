# _too_nested (the lexer check only, no Meta.parse) on every literal in probes/lit/, with time and allocations
using PDEStudioCore
T(s) = PDEStudioCore._too_nested(s)
T("1")
for f in sort(readdir(joinpath(@__DIR__, "lit")))
    s = read(joinpath(@__DIR__, "lit", f), String)
    GC.gc()
    st = @timed T(s)
    println(rpad(f, 32), rpad(string(length(s)), 10), " _too_nested=", rpad(string(st.value), 6), " ", round(st.time; digits = 3), " s, ", round(st.bytes / 2^20; digits = 1), " MiB")
end
