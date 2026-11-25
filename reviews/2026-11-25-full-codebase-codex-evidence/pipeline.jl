using PDEStudioCore
using Logging

Logging.disable_logging(Logging.Warn)
println("Julia ", VERSION, " threads=", Threads.nthreads())
set_target_module!(Main)
variant_solver(p) = create_sim_data([0., 1.], fill(p[:coefficient] isa Float32 ? 10. : 20., 2), p)
unit_solver(p) = create_sim_data([0., 1.], ones(2), p)
source_solver(p) = create_sim_data([0., 1.], fill(coefficient_from_sources, 2), p)
finite_reference(p) = _ -> 3.0
PDEStudioCore.calc_stat(::Val{:finite_fallback}, coords, u, ref, domain) =
    any(v -> isnan(v[1]), ref) ? first(u) : first(ref)

mktempdir() do root
    set_save_path!(root)
    p32 = create_param_dict(:sim_func_name => :variant_solver, :coefficient => 1.5f0)
    p64 = create_param_dict(:sim_func_name => :variant_solver, :coefficient => 1.5)
    c = SimulationConfig(p32; varied = create_varied_dict(:coefficient => Any[1.5f0, 1.5]))
    a, b = get_clean_params(p32)[:coefficient], get_clean_params(p64)[:coefficient]
    println("Mixed scalar sweep: types=", typeof.(c.varied[:coefficient]),
            " distinct raw types=", typeof(p32[:coefficient]) !== typeof(p64[:coefficient]),
            " normalized=", (a, b), " same hash=", calculate_hash(p32) == calculate_hash(p64))
    for (label, config) in (("mixed", c), ("Float32", SimulationConfig(p32)), ("Float64", SimulationConfig(p64)))
        label == "Float32" && set_save_path!(joinpath(root, "single32"))
        label == "Float64" && set_save_path!(joinpath(root, "single64"))
        run = run_all_simulations(config)
        println(label, " tasks=", length(run.tasks), " ran=", length(run.ran), " field=", load_sim_data(only(run.tasks)).u[1][1])
    end
end

mktempdir() do root
    set_save_path!(joinpath(root, "results"))
    a, b = joinpath.(Ref(root), ("a.jl", "b.jl"))
    write(a, "coefficient_from_sources = 10.0\n")
    write(b, "coefficient_from_sources = 20.0\n")
    p = create_param_dict(:sim_func_name => :source_solver)
    c = SimulationConfig(p; sources = [a, b])
    run_all_simulations(c; on_changed_sources = :recompute)
    println("Source order A,B: field=", load_sim_data(p).u[1][1])
    c.sources = [b, a]
    rerun = run_all_simulations(c; on_changed_sources = :recompute)
    println("Source order B,A: changed=", length(rerun.changed), " cached=", length(rerun.cached),
            " field=", load_sim_data(p).u[1][1])
    run_all_simulations(c; force_overwrite = true)
    println("Source order B,A forced: field=", load_sim_data(p).u[1][1])
end

mktempdir() do root
    set_save_path!(root)
    reset_stat_registry!()
    register_stat!(:finite_fallback, Symbol[])
    p = create_param_dict(:sim_func_name => :unit_solver)
    c = SimulationConfig(p)
    a = run_all_simulations(c; calculate_stats = true)
    println("Finite statistic without a reference: ", a.stats, " value=", load_sim_data(p).stats[:finite_fallback][1])
    c.reference = :finite_reference
    b = run_all_simulations(c; calculate_stats = true)
    println("After adding a reference: ", b.stats, " value=", load_sim_data(p).stats[:finite_fallback][1])
    d = run_all_simulations(c; calculate_stats = true, force_stats = true)
    println("After forcing stats: ", d.stats, " value=", load_sim_data(p).stats[:finite_fallback][1])
end
