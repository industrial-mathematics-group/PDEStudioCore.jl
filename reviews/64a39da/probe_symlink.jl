# rehash_sim_data of symlinked files: file/dir targets, delete_old, same hash, relative and dangling links, collisions
using PDEStudioCore, StaticArrays, Test, Logging
using PDEStudioCore: JLD2
root = mktempdir(); set_save_path!(root)
data = joinpath(root, "data"); store = joinpath(root, "store"); mkpath(store)
x = collect(0.0:0.5:1.0)
function linked_file(case; relative = false)
    p = create_param_dict(:case => case, :obsolete => 1)
    save_sim_data(create_sim_data(x, rand(3, 2), [0.0, 1.0], p); verbose = false)
    f = get_file_name(p); target = joinpath(store, basename(f)); mv(f, target)
    relative ? cd(() -> symlink(joinpath("..", "store", basename(f)), basename(f)), data) : symlink(target, f)
    return p, f, target
end
newp(case) = create_param_dict(:case => case)
function logs_of(f)
    l = Test.TestLogger(min_level = Logging.Info)
    r = with_logger(f, l)
    return r, [(r.level, string(r.message)) for r in l.logs]
end
showlogs(logs) = foreach(((lv, m),) -> lv >= Logging.Warn && println("     [", lv, "] ", m), logs)
state(f, t) = "link exists: $(ispath(f) || islink(f)), islink: $(islink(f)), target exists: $(isfile(t))"

println("== file argument, delete_old = true")
p, f, t = linked_file("file")
_, logs = logs_of(() -> rehash_sim_data(f; remove_keys = [:obsolete])); showlogs(logs)
println("   ", state(f, t), ", new file regular: ", !islink(get_file_name(newp("file"))))

println("== directory argument, delete_old = true")
p, f, t = linked_file("dir")
_, logs = logs_of(() -> rehash_sim_data(data; remove_keys = [:obsolete], filter_pairs = Dict(:case => "dir"))); showlogs(logs)
println("   ", state(f, t))

println("== delete_old = false")
p, f, t = linked_file("keep")
_, logs = logs_of(() -> rehash_sim_data(f; remove_keys = [:obsolete], delete_old = false)); showlogs(logs)
println("   warned: ", any(((lv, m),) -> lv == Logging.Warn, logs), "; ", state(f, t))

println("== same hash (nothing removed)")
p, f, t = linked_file("same")
_, logs = logs_of(() -> rehash_sim_data(f)); showlogs(logs)
println("   warned: ", any(((lv, m),) -> lv == Logging.Warn, logs), "; ", state(f, t),
        "; target has dim_keys now: ", JLD2.jldopen(h -> haskey(h, "dim_keys"), t, "r"))

println("== relative link")
p, f, t = linked_file("rel"; relative = true)
println("   readlink: ", readlink(f))
_, logs = logs_of(() -> rehash_sim_data(f; remove_keys = [:obsolete])); showlogs(logs)
println("   ", state(f, t))

println("== dangling link")
p, f, t = linked_file("dangling"); rm(t)
_, logs = logs_of(() -> rehash_sim_data(f; remove_keys = [:obsolete])); showlogs(logs)
_, logs = logs_of(() -> rehash_sim_data(data; remove_keys = [:obsolete], filter_pairs = Dict(:case => "dangling"))); showlogs(logs)
println("   dangling link still there: ", islink(f))
rm(f)

println("== link whose target is in the walked directory too (dedup inside data/)")
p = create_param_dict(:case => "dedup", :obsolete => 1)
save_sim_data(create_sim_data(x, rand(3, 2), [0.0, 1.0], p); verbose = false)
real = get_file_name(p); lnk = joinpath(data, "2000-01-01_00-00-00_000_" * PDEStudioCore._filename_hash(basename(real)) * ".jld2")
symlink(real, lnk)
r, logs = logs_of(() -> rehash_sim_data(data; remove_keys = [:obsolete], filter_pairs = Dict(:case => "dedup"))); showlogs(logs)
println("   result pairs: ", length(r), "; real exists: ", isfile(real), "; link exists: ", islink(lnk),
        "; files for new params: ", length(PDEStudioCore._files_with_hash(PDEStudioCore._param_hash(newp("dedup")))))

println("== collision: the new name is an existing symlink to a shared target (pre-existing behaviour)")
shared_p = newp("collide")
save_sim_data(create_sim_data(x, fill(7.0, 3, 2), [0.0, 1.0], shared_p); verbose = false)
sf = get_file_name(shared_p); st = joinpath(store, "shared.jld2"); mv(sf, st); symlink(st, sf)
po = create_param_dict(:case => "collide", :obsolete => 1)
save_sim_data(create_sim_data(x, fill(1.0, 3, 2), [0.0, 1.0], po); verbose = false)
of = get_file_name(po)
# rename so the stamp matches the link (the new name is <stamp>_<newhash>)
stamp = match(r"^(.+)_[0-9a-f]{64}\.jld2$", basename(sf)).captures[1]
of2 = joinpath(data, stamp * "_" * PDEStudioCore._filename_hash(basename(of)) * ".jld2"); mv(of, of2)
_, logs = logs_of(() -> rehash_sim_data(of2; remove_keys = [:obsolete])); showlogs(logs)
println("   link still a link: ", islink(sf), "; shared target now holds u = ", first(JLD2.load(st, "raw").u)[1], " (was 7.0)")
