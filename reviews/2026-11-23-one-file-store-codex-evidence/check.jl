using PDEStudioCore, JLD2, Logging

params(k; extra...) = create_param_dict(:k => k, extra...)
dataset(p, v) = create_sim_data([0.0, 1.0], fill(Float64(v), 2), p)
save(p, v) = save_sim_data(dataset(p, v); verbose=false)
field(p) = load_sim_data(p).u[1][1]
fresh() = set_save_path!(mktempdir())
const calls = Ref(0)
solver_no_data(p) = (calls[] += 1; NoSimData())

function invalid_raw()
    fresh()
    p = params("run")
    good = save(p, 7)
    original = read(good)
    bad = joinpath(mktempdir(), "bad.jld2")
    cp(good, bad)
    jldopen(bad, "a+") do f
        delete!(f, "raw")
        f["raw"] = "not a simulation dataset"
    end
    imported = import_sim_data(bad; overwrite=true)
    println("invalid raw: imports=",length(imported)," original bytes preserved=",read(good)==original,
            " exists=",does_sim_data_exist(p)," loaded type=",typeof(load_sim_data(p)))
end

function linked_destination()
    fresh()
    p = params("run")
    dest = save(p, 7)
    external = joinpath(mktempdir(), "external.jld2")
    mv(dest, external)
    symlink(external, dest)
    base = params("run"; obsolete=true)
    src = save(base, 9)
    src_before = read(src)
    target_before = read(external)
    imported = import_sim_data(src; remove_keys=[:obsolete], overwrite=true)
    println("linked destination: imports=",length(imported)," direct source unchanged=",read(src)==src_before,
            " external bytes preserved=",read(external)==target_before," destination is link=",islink(dest),
            " external field=",jldopen(f->f["raw"].u[1][1],external))
end

function overlapping_import()
    fresh()
    p = params("run")
    dest = save(p, 7)
    dir = dirname(dest)
    candidate = joinpath(dir, "000-incoming.jld2")
    base = params("run"; obsolete=true)
    mv(save(base, 9), candidate)
    before = read(dest)
    imported = import_sim_data(dir; remove_keys=[:obsolete], overwrite=true)
    println("in-store import: imports=",length(imported)," one original input overwritten=",read(dest)!=before,
            " result=",field(p))
end

function typed_filters()
    fresh()
    p, q = params(1), params(true)
    a, b = save(p, 7), save(q, 9)
    dir = mktempdir()
    mv(a, joinpath(dir, "int.jld2"))
    mv(b, joinpath(dir, "bool.jld2"))
    println("typed import: hashes distinct=",calculate_hash(p)!=calculate_hash(q),
            " selected=",sort(basename.(first.(import_sim_data(dir; filter_pairs=Dict(:k=>1))))))
    println("typed delete: would delete both=",length(delete_sim_data(Dict(:k=>1);dry_run=true))==2)
end

function dangling_slot()
    fresh()
    p=params("run")
    dest=joinpath(get_save_path(),"data",calculate_hash(p)*".jld2")
    missing_target=joinpath(get_save_path(),"separate-mount.jld2")
    symlink(missing_target,dest)
    save(p, 7)
    println("dangling destination: link preserved=",islink(dest)," target created=",isfile(missing_target),
            " now field=",field(p))
end

function retry_partial()
    fresh()
    p = params("retry")
    dest = save(p, 7)
    good = joinpath(mktempdir(), "good.jld2")
    cp(dest, good)
    jldopen(f->delete!(f,"raw"), dest, "a+")
    imported = import_sim_data(good)
    println("retry partial destination: imports=",length(imported)," loadable=",does_sim_data_exist(p))
end

function legacy_fixture(path, seed)
    p = params("legacy"; obsolete=1)
    set_save_path!(path)
    if seed
        sim = dataset(p, 42)
        sim.metadata[:note] = "legacy notes"
        old = save_sim_data(sim; verbose=false)
        println("legacy source emitted by ",pkgversion(PDEStudioCore),": ",basename(old))
    else
        dir = joinpath(path,"data")
        old = only(readdir(dir;join=true))
        before = read(old)
        fresh()
        println("legacy import: initially exists=",does_sim_data_exist(p))
        imported = import_sim_data(dir)
        println("legacy import: imports=",length(imported)," source bytes preserved=",read(old)==before,
                " field=",field(p)," metadata=",load_sim_data(p).metadata[:note])
    end
end

function no_data()
    fresh()
    p=create_param_dict(:sim_func_name=>:solver_no_data)
    dest=joinpath(get_save_path(),"data",calculate_hash(p)*".jld2")
    write(dest,"unreadable placeholder")
    out=run_all_simulations(SimulationConfig(p))
    println("no output solver: called=",calls[]," empty=",length(out.empty)," failed=",length(out.failed))
end

with_logger(NullLogger()) do
    println("Julia ", VERSION, ", hash format ", PDEStudioCore._HASH_FORMAT)
    if !isempty(ARGS)
        legacy_fixture(ARGS[2], ARGS[1] == "seed")
        return
    end
    if isdefined(PDEStudioCore,:import_sim_data)
        invalid_raw()
        linked_destination()
        overlapping_import()
        typed_filters()
        dangling_slot()
        retry_partial()
    else
        fresh()
        save(params(1),7)
        save(params(true),9)
        println("typed delete: would delete both=", length(delete_sim_data(Dict(:k=>1);dry_run=true))==2)
    end
    no_data()
end
