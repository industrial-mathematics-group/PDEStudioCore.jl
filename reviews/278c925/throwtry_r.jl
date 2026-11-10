using PDEStudioCore; const JLD2 = PDEStudioCore.JLD2
struct Foo; x::Vector{String}; end
struct Bar; a::String; end
JLD2.jldopen(ARGS[1], "r") do f
    for k in ("foo", "bar")
        try; v = f[k]; println(k, " => ", typeof(v)); catch e; println(k, " THROWS ", sprint(showerror, e)[1:min(end,200)]); end
    end
end
