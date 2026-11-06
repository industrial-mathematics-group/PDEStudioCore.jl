# Every Symbol named by a JuliaSyntax kind (keywords, operators) and its dotted form, alone and in containers:
# str2val(val2str(v)) at the checked-out code against the reference parser (ARGS[1] = test/reference_str2val.jl);
# parse and hash-text differences, and whether `_too_nested` rejects the text.
using PDEStudioCore, StaticArrays
include(ARGS[1])
const JS = Base.JuliaSyntax
same(a, b) = a === b || (isequal(a, b) && typeof(a) == typeof(b))
names_ = sort!(collect(filter(s -> !isempty(s) && !occursin(r"^[A-Z]", s) && !startswith(s, "BEGIN_") &&
                              !startswith(s, "END_"), collect(keys(JS._kind_str_to_int)))))
syms = Symbol[]
for s in names_
    push!(syms, Symbol(s)); push!(syms, Symbol("." * s))
end
append!(syms, Symbol.(["", " ", ":", "::", ".", "..", "...", "'", "?", "\$", "@", "@a", "#", "begin end", "x=", "=x",
                       ".:", ":.", "::=", ".::", "a.b", "end.", "=>.", "->", ".->"]))
unique!(syms)
nd = nh = nt = 0; nv = 0
for sym in syms
    global nd, nh, nt, nv
    for v in Any[sym, [sym], (sym,), (sym, :a), Dict(sym => 1), Dict(:a => sym), Val(sym), [sym, :begin], Val((sym, 1))]
        local txt = val2str(v)
        nv += 1
        new = str2val(txt); old = OldStr2Val.str2val(txt)
        t = PDEStudioCore._too_nested(strip(txt))
        d = !same(new, old)
        h = val2str(new) != val2str(old)
        d && (nd += 1); h && (nh += 1); (t && !(old isa String)) && (nt += 1)
        if d || h
            println(rpad(repr(sym), 14), rpad(first(txt, 50), 52), " new: ", rpad(string(typeof(new)), 24), " old: ",
                    rpad(string(typeof(old)), 24), " T: ", t, h ? " HASH-TEXT DIFF" : "")
        end
    end
end
println("$(length(syms)) symbols, $nv values: $nd parse differences, $nh hash-text differences, ",
        "$nt rejected by _too_nested although the reference reads a non-String")
