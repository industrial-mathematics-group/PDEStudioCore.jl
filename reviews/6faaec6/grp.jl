using PDEStudioCore; const JLD2 = PDEStudioCore.JLD2
p = tempname() * ".jld2"
JLD2.jldopen(p, "w") do f; f["a"] = 1; f["grp/x"] = 2; end
println(JLD2.load(p))
