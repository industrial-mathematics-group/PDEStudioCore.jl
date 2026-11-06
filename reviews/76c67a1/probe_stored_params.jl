# Read-only: loads the stored "params" of every cached dataset under /workspace/julia/Simulations/data and compares
# the new normalisation (str2val(val2str(v))) with the previous parser (test/reference_str2val.jl).
using PDEStudioCore, StaticArrays
const jldopen = PDEStudioCore.JLD2.jldopen
include("/home/agent/.claude/jobs/d2d299f1/tmp/review-psc1b/repo/test/reference_str2val.jl")
same(a, b) = a === b || (isequal(a, b) && typeof(a) == typeof(b))
files = String[]
for (root, _, fs) in walkdir("/workspace/julia/Simulations/data"), f in fs
    endswith(f, ".jld2") && push!(files, joinpath(root, f))
end
println(length(files), " files")
kinds = Dict{Tuple{Symbol, String}, Int}()
diffs = Dict{String, Any}()
hashdiff = 0; nvals = 0; failed = 0
for f in files
    params = try
        jldopen(fl -> haskey(fl, "params") ? fl["params"] : nothing, f, "r")
    catch e
        global failed += 1; nothing
    end
    params === nothing && continue
    for (k, v) in params
        global nvals += 1
        s = val2str(v)
        kinds[(Symbol(k), string(typeof(v)))] = get(kinds, (Symbol(k), string(typeof(v))), 0) + 1
        new = v isa AbstractString ? String(v) : str2val(s)
        old = v isa AbstractString ? String(v) : OldStr2Val.str2val(s)
        if !same(old, new)
            diffs[s] = (typeof(old), typeof(new))
        end
        val2str(new) == val2str(old) || (global hashdiff += 1)
    end
end
println("values: $nvals, unreadable files: $failed, hash-text differences: $hashdiff")
println("parse differences (old type, new type) by text: ", length(diffs))
for (s, t) in first(collect(diffs), 30); println("  ", first(s, 100), " => ", t); end
println("stored (key, type) kinds: ", length(kinds))
for ((k, T), n) in sort(collect(kinds); by = x -> string(x[1]))
    println("  ", rpad(string(k), 28), rpad(first(T, 70), 72), n)
end
