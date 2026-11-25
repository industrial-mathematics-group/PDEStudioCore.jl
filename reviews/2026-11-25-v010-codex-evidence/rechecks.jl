using PDEStudioCore, Logging
Logging.disable_logging(Logging.Error)

for value in (Any[nothing], Any[missing], Val{reinterpret(Float64, UInt64(0x7ff8000000000001))}())
    try
        calculate_hash(create_param_dict(:v => value))
        println("Unexpectedly accepted: ", repr(value))
    catch error
        error isa ArgumentError || rethrow()
        println("Refused ", repr(value), ": ", sprint(showerror, error))
    end
end

set_stat_preset!("hyperbolic")
registry_solver(p) = create_sim_data([0., 1.], ones(2), p)
registry_a(p) = _ -> 2.0
registry_b(p) = _ -> 4.0
mktempdir() do root
    set_save_path!(root)
    p = create_param_dict(:sim_func_name => :registry_solver)
    c = SimulationConfig(p; reference = :registry_a)
    set_stat_registry!(Dict(:l1error => :time))
    run_all_simulations(c; calculate_stats = true)
    set_stat_registry!(Dict(:l2error => :time))
    run_all_simulations(c; calculate_stats = true)
    c.reference = :registry_b
    run_all_simulations(c; calculate_stats = true)
    register_stat!(:l1error, :time)
    s = run_all_simulations(c; calculate_stats = true)
    println("Re-registering L1 under B: ", s.stats, " L1=", only(load_sim_data(p).stats[:l1error]))
end

set_stat_registry!(Dict(:l2norm => Symbol[]))
data = create_sim_data([0., 1e100], [1e149, 1e149], ParamDict())
calculate_all_stats!(data; save = false)
println("Finite L2 with 1e149 values and 1e100 spacing: reported=", only(data.stats[:l2norm]),
        " expected=", Float64(sqrt(big(2) * big"1e100") * big"1e149"))
