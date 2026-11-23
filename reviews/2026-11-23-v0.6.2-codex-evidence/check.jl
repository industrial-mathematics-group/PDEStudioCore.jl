using PDEStudioCore
using StaticArrays
using Logging

# Every write goes to a new, disposable save root.
new_store() = set_save_path!(mktempdir())
scalar_data(p, v) = create_sim_data([0.0, 1.0], fill(v, 2), p)
review_solver(p) = scalar_data(p, 1.0)
review_reference_one(p) = x -> 1.0
review_reference_two(p) = x -> 2.0
review_type_solver(p) = scalar_data(p, p[:k] isa AbstractString ? 2.0 : 1.0)

function hash_case()
    new_store()
    p = create_param_dict(:sim_func_name => :review_type_solver, :k => 1)
    q = merge(p, Dict(:k => "1"))
    cfg = SimulationConfig(p; varied = create_varied_dict(:k => Any[1, "1"]))
    s = run_all_simulations(cfg)
    println("typed parameters: tasks=", length(s.tasks), ", same hash=", calculate_hash(p) == calculate_hash(q),
            ", requested string result=", load_sim_data(q).u[1][1], " (solver gives 2.0)")
end

function mutation_case()
    new_store()
    p = create_param_dict(:weights => [1.0, 2.0])
    original = deepcopy(p)
    function solver(q)
        q[:weights][1] = 9.0
        return scalar_data(q, 1.0)
    end
    run_smart_simulation(solver, p)
    println("solver parameter copy: caller=", p[:weights], ", original task stored=", does_sim_data_exist(original))
end

function conversion_cache_case()
    new_store()
    p = create_param_dict(:case => :cached_conversion)
    save_sim_data(scalar_data(p, 1.0))
    enable_cache!(true)
    first_read = load_sim_data(p, :lagrangian)
    second_read = load_sim_data(p, :lagrangian)
    new_store()
    calculate_all_stats!(second_read)
    println("derived marker: first=", get(first_read.metadata, :derived, nothing),
            ", cached=", get(second_read.metadata, :derived, nothing),
            ", became native in empty store=", does_sim_data_exist(p))
    enable_cache!(false)
end

function half_precision_case()
    data = create_sim_data(SVector.(Float16[0, 1]), Float16[2, 2], ParamDict())
    out = convert_to_eulerian(data, (2,))
    println("Float16 scatter at two occupied nodes: ", [Float64(v[1]) for v in out.u], " (expected [2, 2])")
end

function statistics_case()
    set_stat_preset!("hyperbolic")
    d = create_sim_data([0.0, 1.0], fill(SVector(1.0, 2.0), 2), ParamDict())
    calculate_all_stats!(d, x -> SVector(0.0, 2.0); save=false)
    println("mixed finite/undefined relative mass: present=", haskey(d.stats, :relative_mass),
            " (second component is 1.0)")
    println("absolute mass error of exact second component: ", d.stats[:mass_error][2])
    add_stat!(d, :spatial, 1.0, :space)
    println("scalar accepted as spatial statistic: stored type=", typeof(d.stats[:spatial]), ", kept=", get_kept_dims(:spatial, d.domain),
            ", stored=", d.stats[:spatial])

    new_store()
    p = create_param_dict(:sim_func_name => :review_solver)
    cfg = SimulationConfig(p; reference=:review_reference_one)
    run_all_simulations(cfg; calculate_stats=true)
    cfg.reference = :review_reference_two
    s = run_all_simulations(cfg; calculate_stats=true)
    cached = load_sim_data(p).stats[:l1error][1]
    run_all_simulations(cfg; calculate_stats=true, force_stats=true)
    println("changed reference: stats cached=", get(s.stats, :cached, 0),
            ", cached L1=", cached, ", fresh L1=", load_sim_data(p).stats[:l1error][1])
    reset_stat_registry!()
end

function upwind_case()
    cfg = test_advection_1d()
    p = merge(cfg.shared, cfg.methods[:upwind], create_param_dict(:N=>4, :c=>-1.0, :T=>0.25, :cfl=>1.0))
    d = PDEStudioCore.Examples.solve_advection_1d(p)
    println("negative-speed upwind: u(x=0.25,t=0.25)=", d.u[2,2][1], " (exact shift gives approximately 0)")
end

function table_case()
    new_store()
    save_sim_data(scalar_data(create_param_dict(:solver=>"alpha"), 1.0))
    save_sim_data(scalar_data(create_param_dict(:param_solver=>"beta"), 2.0))
    tab = sim_data_table()
    println("table column param_solver combines values from distinct keys: ", sort(tab.param_solver))
end

function unreadable_case()
    new_store()
    p = create_param_dict(:sim_func_name => :review_solver)
    file = save_sim_data(review_solver(p))
    # Only this script's temp file is truncated, simulating an incomplete transfer.
    open(io -> truncate(io, 0), file, "w")
    try
        s = run_all_simulations(SimulationConfig(p))
        println("unreadable file: returned summary with ", length(s.failed), " failures")
    catch err
        println("unreadable file: no RunSummary; threw ", typeof(err))
    end
end

function quick_start()
    new_store()
    set_stat_preset!("hyperbolic")
    cfg = test_heat_1d()
    cfg.shared[:N] = 8
    cfg.shared[:T] = 0.01
    cfg.varied[:r] = [0.4]
    s = run_all_simulations(cfg; parallel=true, calculate_stats=true)
    println("reduced heat example: ", length(s.ran), " ran, ", length(s.failed),
            " solver failures, ", length(s.stats_failed), " statistics failures")
    reset_stat_registry!()
end

const fail_review_run = Ref(false)
review_rerun_solver(p) = fail_review_run[] ? error("failed rerun") : scalar_data(p, 1.0)
function review_postprocess(d)
    d.metadata[:completed_after_rerun] = true
    return true
end

function failed_rerun_case()
    new_store()
    cfg = SimulationConfig(create_param_dict(:sim_func_name=>:review_rerun_solver))
    run_all_simulations(cfg)
    cfg.postprocess = :review_postprocess
    fail_review_run[] = true
    s = run_all_simulations(cfg; force_overwrite=true)
    println("failed recomputation: failed=", length(s.failed), ", postprocess ran=", get(s.postprocessing, :ran, 0),
            ", prior file modified=", get(load_sim_data(cfg.shared).metadata, :completed_after_rerun, false))
end

function bigfloat_case()
    data = create_sim_data(BigFloat[0, 1], BigFloat[1, 2], ParamDict())
    try
        println("BigFloat health summary: ", check_data(data))
    catch err
        println("BigFloat health summary failed with ", typeof(err), " in ", err isa MethodError ? err.f : :unknown)
    end
end

with_logger(NullLogger()) do
    quick_start()
    hash_case()
    mutation_case()
    conversion_cache_case()
    half_precision_case()
    statistics_case()
    upwind_case()
    table_case()
    unreadable_case()
    failed_rerun_case()
    bigfloat_case()
end
