using PDEStudioCore, StaticArrays, Logging

identity_solver(p) = create_sim_data([0.0, 1.0], fill(p[:mode] === Val{Symbol("left.mode")} ? 10.0 : 20.0, 2), p)
function tag_collision()
    set_save_path!(mktempdir())
    a = create_param_dict(:sim_func_name => :identity_solver, :mode => Val{Symbol("left.mode")})
    b = create_param_dict(:sim_func_name => :identity_solver, :mode => Val{Symbol("right.mode")})
    sa = run_all_simulations(SimulationConfig(a))
    sb = run_all_simulations(SimulationConfig(b))
    println("tag identity: distinct=", a[:mode] !== b[:mode], " cleaned=", get_clean_params(a)[:mode], " / ", get_clean_params(b)[:mode],
            " same hash=", calculate_hash(a)==calculate_hash(b), " first ran=", length(sa.ran),
            " second cached=", length(sb.cached), " second field=", load_sim_data(b).u[1][1])
end

const GRID_N = 50_000
line_solver(p) = create_sim_data(collect(1.0:GRID_N), collect(1.0:GRID_N), p)
function node_update(d)
    d.u[1] = SVector(101.0)
    return true
end
function sampled_postprocess()
    set_save_path!(mktempdir())
    set_stat_registry!(Dict(:mass => :time))
    p = create_param_dict(:sim_func_name => :line_solver)
    c = SimulationConfig(p; postprocess=:node_update)
    run_all_simulations(c; calculate_stats=true)
    d = load_sim_data(p)
    mass_present = haskey(d.stats, :mass)
    s = run_all_simulations(c; calculate_stats=true)
    d = load_sim_data(p)
    println("large field post-process: first node=", d.u[1][1], " mass present immediately=", mass_present,
            " next stats=", s.stats, " recorded mass=", d.stats[:mass][1], " independent sum=", sum(first, d.u))
end

function reference_warn_with_added_stat()
    set_save_path!(mktempdir())
    set_stat_registry!(Dict(:l1error => :time))
    root = mktempdir()
    solver = joinpath(root, "solver.jl")
    ref = joinpath(root, "ref.jl")
    write(solver, "simple_solver(p) = create_sim_data([0.0, 1.0], [1.0, 1.0], p)\n")
    write(ref, "simple_reference(p) = _ -> 2.0\n")
    p = create_param_dict(:sim_func_name => :simple_solver)
    c = SimulationConfig(p; reference=:simple_reference, sources=[solver, ref])
    run_all_simulations(c; calculate_stats=true)
    old = load_sim_data(p).stats[:l1error][1]
    write(ref, "simple_reference(p) = _ -> 4.0\n")
    normal = run_all_simulations(c; calculate_stats=true)
    register_stat!(:mass, :time)
    expanded = run_all_simulations(c; calculate_stats=true)
    println("reference edit in warn mode: old error=", old, " same registry=", normal.stats,
            " added mass=", expanded.stats, " error after adding mass=", load_sim_data(p).stats[:l1error][1])
end

two_node_solver(p) = create_sim_data([0.0, 1.0], [1.0, 1.0], p)
function processed_error(d)
    d.u .= Ref(SVector(2.0))
    # The callback has its own exact value, 3, so the two nodes each contribute 1.
    add_stat!(d, :l1error, 2.0, :time)
    return true
end
function postprocessor_stat()
    set_save_path!(mktempdir())
    set_stat_registry!(Dict(:l1error => :time))
    p = create_param_dict(:sim_func_name => :two_node_solver)
    c = SimulationConfig(p; postprocess=:processed_error)
    s = run_all_simulations(c; calculate_stats=true)
    before = get(load_sim_data(p).stats, :l1error, missing)
    again = run_all_simulations(c; calculate_stats=true)
    println("post-processor supplied L1: first post=", s.postprocessing, " saved error=", before,
            " next post=", again.postprocessing, " next error=", get(load_sim_data(p).stats, :l1error, missing))
end

function cases()
    println("Julia ", VERSION)
    tag_collision()
    sampled_postprocess()
    reference_warn_with_added_stat()
    postprocessor_stat()
end

with_logger(NullLogger()) do
    set_stat_preset!("hyperbolic")
    Base.invokelatest(cases)
end
