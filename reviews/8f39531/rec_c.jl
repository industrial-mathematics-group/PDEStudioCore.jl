include(joinpath(@__DIR__, "rec_common.jl"))
struct UserNote; a::Int; end
mutable struct MutNote; a::Int; end
f = only(filter(endswith(".jld2"), readdir(joinpath(ARGS[1], "data"); join = true)))
jldopen(f, "r") do file
    for k in ("note", "notes", "dnote", "mnote", "snote", "tnote")
        println(rpad(k, 6), " => ", typeof(file[k]))
    end
end
