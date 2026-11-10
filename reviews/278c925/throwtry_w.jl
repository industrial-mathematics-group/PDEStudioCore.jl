using PDEStudioCore; const JLD2 = PDEStudioCore.JLD2
struct Foo; x::Int; end
struct Bar; a::Float64; b::Vector{Int}; end
JLD2.jldopen(ARGS[1], "w") do f
    f["foo"] = Foo(1); f["bar"] = Bar(1.0, [1,2])
end
