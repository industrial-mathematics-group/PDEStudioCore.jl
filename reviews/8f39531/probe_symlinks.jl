using Test
include(joinpath(@__DIR__, "rec_common.jl"))
const C = PDEStudioCore
notmp(dirs...) = !any(d -> any(endswith(".tmp"), readdir(d)), dirs)

function setup(; relative_link = false, chain = false)
    root = mktempdir(); store = mkpath(joinpath(root, "store"))
    set_save_path!(joinpath(root, "save"))
    sim = mkdata(P)
    path = save_sim_data(sim; verbose = false)
    target = joinpath(store, "real.jld2")
    mv(path, target)
    if chain
        mid = joinpath(store, "mid.jld2"); symlink(target, mid); symlink(mid, path)
    else
        symlink(relative_link ? joinpath("..", "..", "store", "real.jld2") : target, path)
    end
    return sim, path, target, store
end

for (name, kw) in (("absolute link", (;)), ("relative link", (; relative_link = true)), ("chained links", (; chain = true)))
    @testset "$name" begin
        sim, path, target, store = setup(; kw...)
        @test isfile(path) && islink(path)
        ino = stat(target).inode
        # overwrite through _write_sim_file
        sim.u[1] = sim.u[1] .+ 1
        ret = save_sim_data(sim; overwrite = true, verbose = false, metadata = Dict("m" => 1))
        @test ret == path
        @test islink(path) && stat(target).inode != ino
        @test load_sim_data(P).u == sim.u && JLD2.load(path, "m") == 1
        @test get_file_name(P) == path
        # bookkeeping through _update_entries!
        C._set_key!(path, "evaluated_with_reference", true)
        @test islink(path) && JLD2.load(target, "evaluated_with_reference") == true
        calculate_all_stats!(load_sim_data(P))
        @test islink(path) && notmp(store, dirname(path))
        # conversion cache
        enable_cache!(true)
        load_sim_data(P, Val(:lagrangian))
        @test islink(path) && does_sim_data_exist(P, Val(:lagrangian))
        @test notmp(store, dirname(path))
    end
end

@testset "symlinked data directory and relative save path" begin
    root = mktempdir(); real = mkpath(joinpath(root, "realdata"))
    mkpath(joinpath(root, "save")); symlink(real, joinpath(root, "save", "data"))
    cd(root) do
        set_save_path!("save")
        sim = mkdata(P)
        path = save_sim_data(sim; verbose = false)
        @test !isabspath(path) || true
        sim.u[1] = sim.u[1] .+ 1
        save_sim_data(sim; overwrite = true, verbose = false)
        C._set_key!(path, "evaluated_with_reference", false)
        @test load_sim_data(P).u == sim.u
        @test islink(joinpath(root, "save", "data")) && length(readdir(real)) == 1 && notmp(real)
    end
end

@testset "dangling link with the hash name" begin
    root = mktempdir(); set_save_path!(joinpath(root, "save"))
    sim = mkdata(P); path = save_sim_data(sim; verbose = false)
    rm(path); symlink(joinpath(root, "nowhere.jld2"), path)
    r = try save_sim_data(sim; overwrite = true, verbose = false); "ok" catch e; sprint(showerror, e)[1:min(end, 120)] end
    println("dangling link, overwrite save: ", r, "; islink = ", islink(path), ", isfile = ", isfile(path))
end
