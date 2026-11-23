using PDEStudioCore, StaticArrays, Logging
using JLD2: jldopen

data(p,v) = create_sim_data([0.0, 1.0], fill(v, 2), p)
params(k) = create_param_dict(:k => k)
field(p) = only(unique(first.(load_sim_data(p).u)))
rerun_constant(p) = data(p, 1.0)
first_reference(p) = x -> 1.0
second_reference(p) = x -> 2.0

function fresh_hash_case()
    set_save_path!(mktempdir())
    plain, quoted = params("1"), params("\"1\"")
    cfg = SimulationConfig(plain; varied=create_varied_dict(:k=>[plain[:k], quoted[:k]]))
    save_sim_data(data(quoted, 20.0))
    save_sim_data(data(plain, 10.0); overwrite=true)
    println("string sweep: tasks=", length(generate_tasks(cfg)), " stored files=", length(find_sim_data(; verbose=false)),
            " quoted result=", field(quoted), " expected 20")
end

function scatter_case()
    d = create_sim_data(SVector.(Float16[1,255]), Float16[1,3], ParamDict(); xmins=0, xmaxs=256)
    out = convert_to_eulerian(d, (2,))
    println("Float16 scatter: ", Float64.(first.(out.u)), " expected approximately [1, 3]")
end

function reference_case()
    set_save_path!(mktempdir())
    set_stat_preset!("hyperbolic")
    set_stat_registry!(Dict(:l1error=>:time))
    cfg = SimulationConfig(create_param_dict(:sim_func_name=>:rerun_constant); reference=:first_reference)
    run_all_simulations(cfg; calculate_stats=true)
    calculate_all_stats!(load_sim_data(cfg.shared))
    cfg.reference = :second_reference
    s = run_all_simulations(cfg; calculate_stats=true)
    cached = load_sim_data(cfg.shared).stats[:l1error][1]
    run_all_simulations(cfg; calculate_stats=true, force_stats=true)
    println("reference after no-op stats call: cached=", get(s.stats, :cached, 0),
            " stored L1=", cached, " fresh L1=", load_sim_data(cfg.shared).stats[:l1error][1])
    reset_stat_registry!()
end

function direct_constructor_case()
    set_save_path!(mktempdir())
    p = create_param_dict(:weights=>[1.0, 2.0])
    orig = deepcopy(p)
    d = data(p, sum(p[:weights]))
    p[:weights][1] = 9
    save_sim_data(d)
    println("mutated caller after construction: original found=", does_sim_data_exist(orig),
            " mutated input's sum=", sum(p[:weights]), " stored solution=", field(p))
end

function skipped_save_case()
    set_save_path!(mktempdir())
    p = params("native")
    save_sim_data(data(p,1.0))
    d = convert_to_lagrangian(load_sim_data(p))
    save_sim_data(d) # the native file already exists; overwrite defaults to false
    set_save_path!(mktempdir())
    calculate_all_stats!(d)
    println("after skipped save: derived marker=", get(d.metadata,:derived,nothing),
            " second store has native=", does_sim_data_exist(p))
end

function zero_time_case()
    cfg = test_burgers_1d()
    p = merge(cfg.shared, cfg.methods[:lax_friedrichs], create_param_dict(:T=>0.0, :N=>8))
    d = PDEStudioCore.Examples.solve_burgers_1d(p)
    println("zero-duration Burgers: times=", d.axes[end], " last snapshot finite=", all(v->isfinite(v[1]),d.u[:,end]))
end

function docs_case()
    u = [SVector(1.0,2.0), SVector(2.0,3.0)]
    for (name, f) in (("my_error", (u,ana)->sum(abs.(u .- ana))),
                      ("custom_energy", (u,ana)->sum(abs2.(u))))
        try
            println(name, " result=", f(u, zero.(u)))
        catch e
            println(name, " example raised ", typeof(e), " for ", e isa MethodError ? e.f : :unknown)
        end
    end
end

function legacy_metadata_case()
    set_save_path!(mktempdir())
    p = create_param_dict(:n=>5, :kind=>"eul")
    old = joinpath(dirname(Base.active_project()), "test/fixtures/v0.4/data")
    file = only(filter(f -> endswith(f,calculate_hash(p)*".jld2"), readdir(old)))
    path = joinpath(get_save_path(), "data", file)
    cp(joinpath(old,file), path)
    jldopen(f -> (f["evaluated_reference"]="laboratory calibration"),path,"a+")
    before = get(load_sim_data(p).metadata,:evaluated_reference,nothing)
    upgrade_sim_data(path)
    d = load_sim_data(p)
    calculate_all_stats!(d)
    after = get(load_sim_data(p).metadata,:evaluated_reference,nothing)
    disk = jldopen(f->get(f,"evaluated_reference",nothing),path,"r")
    println("0.4 user metadata: loaded=",repr(before)," after upgrade/stats=",repr(after)," top-level entry=",repr(disk))
end

# The shell driver creates a separate temporary store for these two modes.
function seed_legacy(root)
    set_save_path!(root)
    save_sim_data(data(params("1"), 20.0))
    println("legacy writer stored string parameter with field=", field(params("1")))
end
function read_legacy(root)
    set_save_path!(root)
    p = params(1)
    hit = load_sim_data(p)
    println("integer lookup in old store: matched ",repr(hit.params[:k])," field=",field(p))
    save_sim_data(data(p, 10.0); overwrite=true)
    println("after overwriting integer: original string still findable=", !isempty(find_sim_data(params("1"); verbose=false)))
end

with_logger(NullLogger()) do
    println("PDEStudioCore ", pkgversion(PDEStudioCore))
    if isempty(ARGS)
        fresh_hash_case()
        scatter_case()
        reference_case()
        direct_constructor_case()
        skipped_save_case()
        zero_time_case()
        docs_case()
        legacy_metadata_case()
    elseif ARGS[1]=="seed"
        seed_legacy(ARGS[2])
    elseif ARGS[1]=="read"
        read_legacy(ARGS[2])
    end
end
