using PDEStudioCore, StaticArrays, Logging, SHA
using JLD2: jldopen

param(v) = create_param_dict(:k => v)
dataset(p, v) = create_sim_data([0.0, 1.0], fill(Float64(v), 2), p)
field(p) = first(first(load_sim_data(p).u))
marker() = joinpath(get_save_path(), "data", "PDEStudioCore.toml")
countfiles() = count(f -> endswith(f, ".jld2"), readdir(dirname(marker())))
file_digest(path) = bytes2hex(open(sha256, path))
const plain = "hello"
const quoted = repr(plain)

# This mode starts with an empty working directory, the documented default save root.
function common()
    @assert !isdir(joinpath(pwd(), "data")) && get_save_path() == pwd()
    save_sim_data(dataset(param(1), 1))
    println("first default save: marker=", isfile(marker()))
    try
        save_sim_data(dataset(param(2), 2))
        println("second default save: succeeded")
    catch e
        println("second default save: ", occursin("rehash_sim_data", sprint(showerror, e)) ? "requires rehash" : typeof(e))
    end
    set_save_path!(mktempdir())
    a = create_param_dict(:a => "label", :b => 2)
    b = create_param_dict(Symbol("a => \"label\", b") => 2)
    save_sim_data(dataset(a, 20))
    save_sim_data(dataset(b, 10); overwrite=true)
    println("distinct parameter keys: same hash=", calculate_hash(a)==calculate_hash(b),
            " files=", countfiles(), " first field=", field(a), " expected=20")

    a, b = param(nothing), param(Nothing)
    set_save_path!(mktempdir())
    save_sim_data(dataset(a, 30))
    save_sim_data(dataset(b, 40); overwrite=true)
    println("nothing and its type: normalized equal=", isequal(get_clean_params(a), get_clean_params(b)),
            " same hash=", calculate_hash(a)==calculate_hash(b), " first field=", field(a), " expected=30")

    d = create_sim_data(SVector.(Float16[-40000, 40000]), Float16[1,3], ParamDict(); xmins=-40000, xmaxs=40000)
    try
        result = convert_to_eulerian(d, (3,))
        println("wide Float16 grid: ", Float64.(first.(result.u)), " expected endpoints 1,3")
    catch e
        println("wide Float16 grid: conversion failed; InexactError=", occursin("InexactError", sprint(showerror, e)))
    end
end

function seed(root)
    set_save_path!(joinpath(root, "overlap"))
    for (value, number) in [(plain, 10), (quoted, 20)]
        path = save_sim_data(dataset(param(value), number))
        # Two independent jobs can write in the same millisecond. Fix just the time prefix to model that case.
        mv(path, joinpath(dirname(path), "2026-11-23_12-00-00_000_" * calculate_hash(param(value)) * ".jld2"))
    end
    println("seed overlap: files=", countfiles(), " fields=", (field(param(plain)), field(param(quoted))))
    set_save_path!(joinpath(root, "keep"))
    save_sim_data(dataset(param(quoted), 20))
    set_save_path!(joinpath(root, "readonly"))
    save_sim_data(dataset(param(1), 10))
    set_save_path!(joinpath(root, "incomplete"))
    path = save_sim_data(dataset(param(plain), 10))
    cp(path, joinpath(root, "intact.jld2"))
    write(path, "incomplete file")
    upgrade04(root)
end

function upgrade04(root)
    set_save_path!(joinpath(root, "upgrade"))
    fixture_dir = joinpath(dirname(Base.active_project()), "test/fixtures/v0.4/data")
    p = create_param_dict(:n=>5, :kind=>"eul")
    file = only(filter(f->endswith(f, calculate_hash(p)*".jld2"), readdir(fixture_dir)))
    target = joinpath(dirname(marker()), file)
    cp(joinpath(fixture_dir,file), target)
    jldopen(f -> (f["evaluated_reference"]="laboratory calibration"),target,"a+")
    upgrade_sim_data(target)
    println("0.6 upgrade alone: user value in metadata=", repr(get(load_sim_data(p).metadata,:evaluated_reference,nothing)))
end

function inspect(root)
    set_save_path!(joinpath(root, "overlap"))
    rehash_sim_data()
    println("default rehash: files=", countfiles(), " plain field=", field(param(plain)),
            " quoted exists=", does_sim_data_exist(param(quoted)))
    set_save_path!(joinpath(root, "keep"))
    rehash_sim_data(; delete_old=false)
    hit = load_sim_data(param(plain))
    println("keep old names: marker=",isfile(marker())," lookup hello returns quoted=",hit.params[:k]==quoted,
            " field=",first(first(hit.u)))
    set_save_path!(joinpath(root, "readonly"))
    path = get_file_name(param(1))
    before = file_digest(path)
    enable_cache!(true)
    load_sim_data(param(1), :lagrangian)
    enable_cache!(false)
    println("conversion read: marker=",isfile(marker())," old file changed=",before!=file_digest(path),
            " entries=", list_available_conversions(param(1)))
    set_save_path!(joinpath(root, "incomplete"))
    path = only(filter(f->endswith(f,".jld2"), readdir(dirname(marker());join=true)))
    rehash_sim_data()
    cp(joinpath(root,"intact.jld2"), path; force=true)
    save_sim_data(dataset(param(plain), 99))
    println("incomplete rehash after file restore: marker=",isfile(marker())," files=",countfiles(),
            " returned field=",field(param(plain))," original field=10")
    inspect04(root)
end

function inspect04(root)
    set_save_path!(joinpath(root,"upgrade"))
    rehash_sim_data()
    p = create_param_dict(:n=>5, :kind=>"eul")
    d = load_sim_data(p)
    println("0.7 after documented upgrade: user value in metadata=",repr(get(d.metadata,:evaluated_reference,nothing)))
end
review_solver(p) = dataset(p, 17)
function missing_raw()
    set_save_path!(mktempdir())
    p = create_param_dict(:sim_func_name=>:review_solver)
    cfg = SimulationConfig(p)
    run_all_simulations(cfg)
    path = get_file_name(p)
    jldopen(f -> delete!(f,"raw"), path, "a+")
    exists = does_sim_data_exist(p)
    result = run_all_simulations(cfg)
    println("missing raw: exists=",exists," cached=",length(result.cached)," reran=",length(result.ran),
            " raw after run=",jldopen(f->haskey(f,"raw"),path,"r"))
end

with_logger(NullLogger()) do
    println("PDEStudioCore ", pkgversion(PDEStudioCore), " Julia ", VERSION)
    if ARGS[1] == "common"
        common()
    elseif ARGS[1] == "seed"
        seed(ARGS[2])
    elseif ARGS[1] == "damaged"
        missing_raw()
    elseif ARGS[1] == "upgrade04"
        upgrade04(ARGS[2])
    elseif ARGS[1] == "inspect04"
        inspect04(ARGS[2])
    elseif ARGS[1] == "inspect"
        inspect(ARGS[2])
    end
end
