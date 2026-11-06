# The new reconstruction tests evaluated with 6e36904's _is_reconstructed, and the new symlink test on the old code
using PDEStudioCore, StaticArrays, Test
using PDEStudioCore: JLD2
old_is_reconstructed(value) = occursin(r"JLD2\.(Reconstructed|Serialized)", string(typeof(value)))
anon = Module(); Core.eval(anon, :(struct Hidden; a::Int; end))
f = joinpath(mktempdir(), "hidden.jld2")
JLD2.jldsave(f; t = anon.Hidden, anyv = Any[1, Base.invokelatest(anon.Hidden, 2)],
             d = Dict{Symbol, Any}(:h => anon.Hidden), nested = Any[Any[(1, anon.Hidden)]])
for k in ("t", "anyv", "d", "nested")
    println(rpad("old _is_reconstructed($k)", 40), old_is_reconstructed(JLD2.load(f, k)))
end
println("is the old code loaded: ", isdefined(PDEStudioCore, :_reconstructed_type) ? "no (new)" : "yes")
set_save_path!(mktempdir())
p_link = create_param_dict(:N => 12, :scheme => "upwind", :cfl => 0.5, :obsolete => "x", :test_mode => "link")
x = collect(0.0:0.1:1.0)
save_sim_data(create_sim_data(x, rand(11, 2), [0.0, 1.0], p_link); overwrite = true)
linked = get_file_name(p_link)
target = joinpath(mktempdir(), basename(linked)); mv(linked, target); symlink(target, linked)
ts = @testset "symlink test on this code" begin
    @test_logs (:warn, r"is a symlink.*is kept"s) match_mode = :any rehash_sim_data(linked; remove_keys = [:obsolete])
    @test isfile(target) && !ispath(linked)
end
