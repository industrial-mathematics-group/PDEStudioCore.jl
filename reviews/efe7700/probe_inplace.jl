# Probe: calculate_all_stats!(save = true) modifies the data file in place (not via temp file + rename)
using Test, PDEStudioCore, StaticArrays, Logging
global_logger(ConsoleLogger(stderr, Logging.Warn))
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())
@testset "in-place writes" begin
    x = collect(range(0.0, 1.0, length = 50))
    sim = create_sim_data(x, [SVector(sin(xi) + ti) for xi in x, ti in 0:0.1:1], collect(0:0.1:1), create_param_dict(:tag => "inplace"))
    calculate_all_stats!(sim)                     # writes file (atomic) + _set_key! (in place)
    f = get_file_name(sim.params)
    ino = stat(f).inode; sz = filesize(f)
    # same stats, no reference -> nothing changed, but evaluated_with_reference flips => in-place rewrite
    calculate_all_stats!(sim, xt -> SVector(sin(xt[1]) + xt[2]))   # errors added -> changed -> atomic rewrite
    ino2 = stat(f).inode
    calculate_all_stats!(sim)                     # nothing changed: only _set_key!("evaluated_with_reference", false)
    ino3 = stat(f).inode
    @show ino ino2 ino3
    @test ino2 != ino && ino3 == ino2             # third call modified the file in place
    sizes = Int[]
    for i in 1:20
        PDEStudioCore._set_key!(f, "evaluated_with_reference", isodd(i))
        push!(sizes, filesize(f))
    end
    @show sizes[1] sizes[end]
end
@testset "empty particle step message" begin
    x = [[SVector(0.0), SVector(1.0)], SVector{1, Float64}[]]
    l = create_sim_data(x, x, [0.0, 1.0], create_param_dict(:tag => "empty-step"))
    try calculate_all_stats!(l; save = false) catch e; println(sprint(showerror, e)[1:min(end, 200)]) end
end
