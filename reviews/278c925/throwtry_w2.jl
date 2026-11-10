using PDEStudioCore; const JLD2 = PDEStudioCore.JLD2
myfun(x) = x + 1
module M2; struct Q; x::Int; end; end
JLD2.jldopen(ARGS[1], "w") do f
    f["anon"] = x -> x + 1
    f["named"] = myfun
    f["mod"] = M2.Q(1)
    f["typ"] = M2.Q
end
