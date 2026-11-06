# Writes nested literals to lit/nest_*.txt
d = joinpath(@__DIR__, "lit")
w(name, s) = write(joinpath(d, "nest_$name.txt"), s)
for n in (20, 50, 100)
    w("dict$n", "Dict(1 => "^n * "1" * ")"^n)
    w("vec$n", "["^n * "1" * "]"^n)
    w("tup$n", "("^n * "1" * ",)"^n)
    w("mix$n", join(["[" * "("^k * "1" * ",)"^k * "]" for k in 1:n÷4], ", ") |> s -> "(" * s * ",)")
end
w("sadict20", "SA[" * join(["Dict(1 => " * "["^k * "1" * "]"^k * ")" for k in 1:10], ", ") * "]")
for n in (1000, 10^4, 10^5)
    w("vec$n", "["^n * "1" * "]"^n)
    w("tup$n", "("^n * "1" * ",)"^n)
    w("tupletype$n", "Tuple{"^n * "Int" * "}"^n)
    w("paren$n", "("^n * "1" * ")"^n)
end
w("vec1000000", "["^10^6 * "1" * "]"^10^6)
