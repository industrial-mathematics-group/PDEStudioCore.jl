using PDEStudioCore, Test
const J = PDEStudioCore.JLD2
anon = Module()
Core.eval(anon, :(struct Hidden; a::Int; end))
dir = mktempdir()
src_file = joinpath(dir, "src.jld2"); dst_file = joinpath(dir, "dst.jld2")
J.jldsave(src_file; v = [Base.invokelatest(anon.Hidden, 1)], s = Base.invokelatest(anon.Hidden, 2), d = Dict(1 => Base.invokelatest(anon.Hidden, 3)))
logs = J.jldopen(src_file, "r") do src
    J.jldopen(dst_file, "w") do dest
        Test.collect_test_logs() do
            for k in ("v", "s", "d"); PDEStudioCore._copy_entry!(dest, src, k); end
        end[1]
    end
end
for l in logs; l.level == Base.CoreLogging.Warn && occursin("Entry", string(l.message)) && println(l.message); end
