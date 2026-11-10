using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
f = first(filter(endswith(".jld2"), readdir(joinpath(ARGS[1], "data"); join = true)))
x = try JLD2.load(f, "raw") catch e; e end
println(typeof(x))
