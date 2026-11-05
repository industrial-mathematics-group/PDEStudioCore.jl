using PDEStudioCore, PDEStudioCore.JLD2
jl = Base.julia_cmd(); proj = Base.active_project()
f = joinpath(mktempdir(), "foreign.jld2")
run(`$jl --project=$proj -e "using PDEStudioCore.JLD2; struct ForeignEntry; a::Int; end; jldsave(\"$f\"; foo = ForeignEntry(7))"`)
println("-- jldopen r + haskey"); jldopen(x -> haskey(x, "zzz"), f, "r")
println("-- jldopen a+"); g = f * ".copy"; cp(f, g); jldopen(x -> nothing, g, "a+")
println("-- jldopen a+ and write"); jldopen(x -> (x["k"] = 1), g, "a+")
