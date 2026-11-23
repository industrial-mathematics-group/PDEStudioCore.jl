using PDEStudioCore, StaticArrays, Logging
using JLD2: jldopen

p(value) = create_param_dict(:k => value)
dataset(params, value) = create_sim_data([0.0,1.0], fill(Float64(value),2), params)
save(params, value; kw...) = save_sim_data(dataset(params,value); verbose=false, kw...)
stored(path) = jldopen(f -> (f["params"][:k], first(first(f["raw"].u))), path, "r")
function fresh()
    root = mktempdir()
    set_save_path!(root)
    return joinpath(root,"data")
end
function stale_identity()
    fresh()
    a = save(p("A"), 10)
    b = save(p("B"), 20)
    # Model an atomic replacement preserving file times while a reader is running.
    run(`touch -r $a $b`)
    get_file_name(p("A"))
    mv(b, a; force=true)
    println("cached identity: alternate payload before save=",stored(a))
    try
        save(p("A"), 30; overwrite=true)
    catch e
        println("cached identity: overwrite refused=",occursin("not replaced",sprint(showerror,e)))
    end
    println("cached identity: original path after save=",stored(a))
end
function typed_identity()
    dir = fresh()
    b = save(p(true), 20)
    a = joinpath(dir,"restored_"*calculate_hash(p(1))*".jld2")
    mv(b,a)
    println("typed identity: bool/int hashes differ=",calculate_hash(p(true))!=calculate_hash(p(1)))
    try
        save(p(1), 30; overwrite=true)
    catch e
        println("typed identity: overwrite refused=",occursin("not replaced",sprint(showerror,e)))
    end
    println("typed identity: original path after save=",stored(a))
end
function staging()
    dir = fresh()
    early = joinpath(dir,"a_"*"0"^64*".jld2")
    longfile = joinpath(dir,"z"^182*"_"*"1"^64*".jld2")
    mv(save(p("short"), 1),early)
    mv(save(p("long"), 2),longfile)
    try
        rehash_sim_data(dir)
    catch e
        println("staging: aborted=",occursin("too long",lowercase(sprint(showerror,e))))
    end
    # Retry the operation through the same public entry point.
    try rehash_sim_data(dir) catch end
    println("staging: short run visible=",length(find_sim_data(p("short");verbose=false)),
            " long run visible=",length(find_sim_data(p("long");verbose=false)),
            " residual temporary files=",count(f->endswith(f,".tmp"),readdir(dir)))
end
function linked_sources()
    dir = fresh()
    both = create_param_dict(:k=>"target",:obsolete=>1)
    path = save(both, 20)
    target = joinpath(dir,"z_"*calculate_hash(both)*".jld2")
    mv(path,target)
    link = joinpath(dir,"a_"*calculate_hash(both)*".jld2")
    symlink(basename(target),link)
    result = rehash_sim_data(dir; remove_keys=[:obsolete])
    println("source link plus target: completed=",length(result),
            " readable rehashed runs=",length(find_sim_data(p("target");verbose=false)),
            " hidden links=",count(f->endswith(f,".tmp") && islink(joinpath(dir,f)), readdir(dir)))
end
function cleanup()
    dir = fresh()
    original=save(p("A"),10)
    other=save(p("B"),20)
    wrong=joinpath(dir,"z_"*calculate_hash(p("A"))*".jld2")
    mv(other,wrong)
    run(`touch -r $original $wrong`)
    println("tidy: before, lookup A returns ",stored(get_file_name(p("A"))))
    result=tidy_sim_data()
    println("tidy: deleted only A=",original in result.duplicates," remaining fields=",last.(stored.(find_sim_data(;verbose=false))))
end
function integer_grid()
    d = DomainInfo{1,Int}((:x,),(0,),(1,),(1,),nothing)
    particles = LSimData(ParamDict(),d,[0],[[SVector(0),SVector(1)]],[[SVector(2),SVector(2)]])
    try
        println("integer grid: ",first.(convert_to_eulerian(particles,(2,)).u))
    catch e
        println("integer grid: ",typeof(e)," in _wide=",occursin("_wide",sprint(showerror,e)))
    end
end
function retained_params()
    isdefined(PDEStudioCore,:_STORED_PARAMS) || return println("parameter cache: absent")
    cache = PDEStudioCore._STORED_PARAMS
    start = Base.summarysize(cache)
    seen = String[]
    for n in 1:16
        fresh()
        q = p(string(n)*repeat("x",65536))
        push!(seen,save(q, n))
        get_file_name(q)
        delete_sim_data(q)
    end
    fresh()
    GC.gc()
    println("parameter cache: deleted paths retained=",count(k->haskey(cache,k),seen),
            " additional bytes=",Base.summarysize(cache)-start)
end
with_logger(NullLogger()) do
    println("hash format ",PDEStudioCore._HASH_FORMAT,", Julia ",VERSION)
    stale_identity()
    typed_identity()
    staging()
    linked_sources()
    cleanup()
    integer_grid()
    retained_params()
end
