# _too_nested (lexer only) of every generated literal
using PDEStudioCore
for f in sort(readdir(joinpath(@__DIR__, "lit"))); s = read(joinpath(@__DIR__, "lit", f), String)
    t = @elapsed r = PDEStudioCore._too_nested(s); println(rpad(f, 34), " T = ", rpad(r, 6), " ", sizeof(s), " B, ", round(t; digits = 3), " s"); end
