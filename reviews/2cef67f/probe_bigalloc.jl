using PDEStudioCore
const P = PDEStudioCore
for s in ["BigInt(1):BigInt(10)^6", "BigInt(1):BigInt(10)^5", "BigFloat(1):BigFloat(1e6)", "BigFloat(1):BigFloat(1e5)"]
    for rep in 1:2
        ex = Meta.parse(s)
        a1 = @allocated(v = P._literal(ex))
        a2 = @allocated(n = P._literal_size(v))
        a3 = @allocated(Base.checked_length(v))
        a4 = @allocated(length(v))
        println(rpad(s, 30), " rep=$rep  _literal=", a1, "  _literal_size=", a2, "  checked_length=", a3, "  length=", a4)
    end
end
r = BigInt(1):BigInt(10)^6
println("x isa AbstractArray → length check: ", @allocated(r isa AbstractArray && length(r) > 10^6))
println("_literal_size twice: ", @allocated(P._literal_size(r)))
