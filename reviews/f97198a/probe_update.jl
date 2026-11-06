using PDEStudioCore, StaticArrays, Test
const JLD2 = PDEStudioCore.JLD2; using .JLD2: jldopen
const P = PDEStudioCore
set_save_path!(mktempdir())
x = collect(range(0.0, 1.0, length = 5))
d = create_sim_data(x, fill(SVector(1.0), 5, 2), [0.0, 1.0], create_param_dict(:case => "upd"))
f = save_sim_data(d; verbose = false)
@testset "growth per update" begin
    s = [filesize(f)]
    P._update_entries!(f, Dict{String, Any}("evaluated_stats" => [:mass, :l1norm], "evaluated_with_reference" => false))
    push!(s, filesize(f))
    for v in 1:20
        P._set_key!(f, "evaluated_with_reference", isodd(v)); push!(s, filesize(f))
    end
    for v in 1:5
        P._set_key!(f, "evaluated_stats", Symbol.("s", 1:v)); push!(s, filesize(f))
    end
    println("sizes: ", s); println("diffs: ", diff(s))
    @test load_sim_data(create_param_dict(:case => "upd")).u == d.u
    @test jldopen(ff -> ff["evaluated_with_reference"], f, "r") == false
end
@testset "error while writing leaves file and no tmp" begin
    m0 = read(f)
    r = try P._set_key!(f, "bad", (a = 1, g = Threads.Condition())); :ok catch e; typeof(e) end
    println("unwritable value: ", r)
    @test !any(endswith(".tmp"), readdir(dirname(f)))
end
@testset "symlinked data file" begin
    target = joinpath(mktempdir(), "real.jld2")
    mv(f, target); symlink(target, f)
    before = read(target)
    r = try P._set_key!(f, "evaluated_with_reference", true); :ok catch e; sprint(showerror, e)[1:60] end
    println("update: ", r)
    println("tmp left: ", filter(endswith(".tmp"), readdir(dirname(f))))
    println("after update: islink(f) = ", islink(f), ", target modified in place = ", read(target) != before, ", flag in target = ", jldopen(ff -> ff["evaluated_with_reference"], target, "r"))
end
