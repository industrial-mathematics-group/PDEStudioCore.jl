using PDEStudioCore, Logging
using PDEStudioCore.StaticArrays: SVector
Logging.disable_logging(Logging.Error)

layer_solver(p) = create_sim_data(([0., 1.], [0., 1.]), ones(2, 2), p)
function attach_solver(p)
    d = layer_solver(p)
    add_stat!(d, :weights, [2., 3.], :x)
    return d
end
layer_post(d) = (add_stat!(d, :weighted_total, sum(first, d.stats[:weights]), Symbol[]); true)
function change_schema(d)
    d.domain.stat_registry[:weights] = :y
    return true
end
function change_shape(d)
    d.stats[:weights] = reshape(d.stats[:weights], 2, 1)
    return true
end
layer_ref(p) = _ -> 2.0
bad_ref(p) = error("reference factory cannot initialize")
PDEStudioCore.calc_stat(::Val{:layer_mass}, coords, u, domain) = sum(first, u)

mktempdir() do root
    set_save_path!(root)
    reset_stat_registry!()
    p = create_param_dict(:sim_func_name => :attach_solver)
    c = SimulationConfig(p; postprocess = :layer_post)
    run_all_simulations(c; calculate_stats = true)
    d = load_sim_data(p)
    println("Initially: weights=", first.(d.stats[:weights]), " post=", first(d.stats[:weighted_total]))
    add_stat!(d, :weights, [10., 20.], :x)
    save_sim_data(d; overwrite = true, verbose = false)
    s = run_all_simulations(c; calculate_stats = true)
    d = load_sim_data(p)
    println("After changing simulation statistic: ", s.stats, " ", s.postprocessing, " weights=", first.(d.stats[:weights]),
            " post=", first(d.stats[:weighted_total]))
    s = run_all_simulations(c; calculate_stats = true, force_postprocess = true)
    println("Forced post: ", s.postprocessing, " post=", first(load_sim_data(p).stats[:weighted_total]))

    c.postprocess = :change_schema
    r = run_all_simulations(c)
    d = load_sim_data(p)
    println("Change kept axes from callback: ", r.postprocessing, " kept=", get_kept_dims(:weights, d.domain),
            " layer=", stat_layer(d, :weights))
    c.postprocess = :change_shape
    r = run_all_simulations(c)
    d = load_sim_data(p)
    println("Reshape upstream statistic from callback: ", r.postprocessing, " size=", size(d.stats[:weights]),
            " kept=", get_kept_dims(:weights, d.domain))
end

mktempdir() do root
    set_save_path!(root)
    set_stat_registry!(Dict(:layer_mass => Symbol[]))
    p = create_param_dict(:sim_func_name => :layer_solver)
    c = SimulationConfig(p; reference = :bad_ref)
    s = run_all_simulations(c; calculate_stats = true)
    println("Only a simulation statistic registered, configured reference factory fails: ", s.stats,
            " mass present=", haskey(load_sim_data(p).stats, :layer_mass))
    c.reference = nothing
    s = run_all_simulations(c; calculate_stats = true)
    println("Same dataset without reference: ", s.stats, " mass=", first(load_sim_data(p).stats[:layer_mass]))
end
