# _too_nested (lexer only) of every generated literal in the folders ARGS
using PDEStudioCore
for dir in ARGS, f in sort(readdir(joinpath(@__DIR__, dir))); s = read(joinpath(@__DIR__, dir, f), String)
    t = @elapsed r = PDEStudioCore._too_nested(s); println(rpad(dir * "/" * f, 40), " T = ", rpad(r, 6), " ", sizeof(s), " B, ", round(t; digits = 3), " s"); end
