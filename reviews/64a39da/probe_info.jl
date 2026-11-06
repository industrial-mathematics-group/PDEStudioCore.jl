# get_sim_data_info for every data kind: new files, old files (ARGS[1], written by write_old.jl with 6e36904),
# bookkeeping rewrites, overwrite, rehash, stale entries.
include(joinpath(@__DIR__, "datasets.jl"))
using PDEStudioCore: JLD2
const NFAIL = Ref(0)
check(label, cond) = (cond || (NFAIL[] += 1); println(rpad(label, 70), cond ? "ok" : "FAIL"))
expected_steps(d::ESimData) = has_time(d) ? length(d.axes[end]) : 0
expected_steps(d::LSimData) = has_time(d) ? length(d.t) : 0
expected_shape(d::ESimData) = size(d.u)
expected_shape(d::LSimData) = (length(d.t), sum(length, d.x; init = 0))
haskeys(path) = JLD2.jldopen(f -> (haskey(f, "dim_keys"), haskey(f, "time_dim")), path, "r")
function check_info(label, params)
    d = load_sim_data(params)
    info = get_sim_data_info(params)
    ok = info.kind === (d isa ESimData ? :eulerian : :lagrangian) && info.shape == expected_shape(d) &&
         info.dim_keys == d.domain.dim_keys && info.time_dim === d.domain.time_dim && info.n_steps == expected_steps(d) &&
         info.path == get_file_name(params) && info.n_steps isa Int
    ok || println("   info = ", info, "\n   data dims = ", d.domain.dim_keys, " time_dim = ", d.domain.time_dim)
    check(label, ok)
    return info
end

println("== new files")
set_save_path!(mktempdir())
for (name, d) in make_datasets()
    save_sim_data(d; verbose = false)
    info = check_info("new $name", d.params)
    check("  new $name has dim_keys/time_dim", haskeys(info.path) == (true, true))
    println("   ", (; info.kind, info.shape, info.dim_keys, info.time_dim, info.n_steps))
end

println("== old files (written by 6e36904)")
old = ARGS[1]
work = mktempdir(); cp(joinpath(old, "data"), joinpath(work, "data"))
set_save_path!(work)
for (name, d) in make_datasets()
    p = create_param_dict(:case => name)
    check("old $name lacks dim_keys", haskeys(get_file_name(p)) == (false, false))
    check_info("old $name", p)
end

println("== bookkeeping updates on old files keep the fallback working")
enable_cache!(true)
for (name, d) in make_datasets()
    p = create_param_dict(:case => name)
    sim = load_sim_data(p)
    calculate_all_stats!(sim)                       # _update_entries! ("evaluated_stats")
    load_sim_data(p, Val(:lagrangian))              # conv_L cache for Eulerian
    if sim isa ESimData
        load_sim_data(p, :eulerian, map(n -> max(n - 1, 1), size(sim.u)))   # conv_E cache
    end
    check_info("after stats/caches $name (dim_keys? $(haskeys(get_file_name(p))))", p)
end
enable_cache!(false)

println("== save_sim_data(...; overwrite = true) on old files adds the entries")
for (name, d) in make_datasets()
    p = create_param_dict(:case => name)
    sim = load_sim_data(p)
    save_sim_data(sim; overwrite = true, verbose = false)
    check("overwrite $name has entries", haskeys(get_file_name(p)) == (true, true))
    check_info("overwrite $name", p)
end

println("== rehash of old files")
work2 = mktempdir(); cp(joinpath(old, "data"), joinpath(work2, "data"))
set_save_path!(work2)
pairs = rehash_sim_data(joinpath(work2, "data"); remove_keys = [:nothing_here])
println("   rehashed ", length(pairs), " (same hash: rewritten in place)")
for (name, d) in make_datasets()
    p = create_param_dict(:case => name)
    check("rehash $name has entries", haskeys(get_file_name(p)) == (true, true))
    check_info("rehash $name", p)
end

println("== overwrite with a different layout under the same params: nothing stale")
set_save_path!(mktempdir())
p = create_param_dict(:case => "layout")
x = collect(0.0:0.25:1.0)
save_sim_data(create_sim_data(x, rand(5, 4), [0.0, 1, 2, 3], p); verbose = false)
check_info("layout v1 transient :t", p)
save_sim_data(create_sim_data((x, x), rand(5, 5), p; dims = (:r, :s)); overwrite = true, verbose = false)
i2 = check_info("layout v2 static (:r,:s)", p)
check("  v2 time_dim nothing, n_steps 0", i2.time_dim === nothing && i2.n_steps == 0 && i2.dim_keys == (:r, :s))
save_sim_data(create_sim_data([[SVector(1.0)], [SVector(2.0), SVector(3.0)]], [[SVector(1.0)], [SVector(2.0), SVector(3.0)]],
                              [0.0, 1.0], p; time_dim = :τ); overwrite = true, verbose = false)
i3 = check_info("layout v3 Lagrangian :τ", p)
check("  v3", i3.kind === :lagrangian && i3.shape == (2, 3) && i3.time_dim === :τ && i3.n_steps == 2)
# not overwritten: stays v3
save_sim_data(create_sim_data(x, rand(5, 4), [0.0, 1, 2, 3], p); verbose = false)
check("  save without overwrite keeps v3", get_sim_data_info(p) == i3)

println("== reserved metadata keys")
r = try save_sim_data(create_sim_data(x, rand(5, 4), [0.0, 1, 2, 3], create_param_dict(:case => "meta"));
                      metadata = Dict("time_dim" => "user"), verbose = false); "accepted" catch e; sprint(showerror, e) end
println("   save_sim_data(metadata = \"time_dim\" => ...) -> ", r)

println("== an old file whose user metadata was named \"dim_keys\"/\"time_dim\" (allowed by 6e36904)")
work3 = mktempdir(); mkpath(joinpath(work3, "data"))
cp(joinpath(old, "meta"), joinpath(work3, "meta"))
set_save_path!(joinpath(work3, "meta"))
pm = create_param_dict(:case => "usermeta")
println("   info: ", get_sim_data_info(pm))
d = load_sim_data(pm); println("   data: dim_keys = ", d.domain.dim_keys, ", time_dim = ", d.domain.time_dim)
save_sim_data(d; overwrite = true, verbose = false)
println("   after overwrite: user entries = ", JLD2.jldopen(f -> (f["dim_keys"], f["time_dim"]), get_file_name(pm), "r"))

println("== errors")
set_save_path!(mktempdir())
r = try get_sim_data_info(create_param_dict(:case => "none")); "no error" catch e; typeof(e) end
println("   missing data dir/file -> ", r)
println("FAILURES: ", NFAIL[])
