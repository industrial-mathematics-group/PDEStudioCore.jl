using PDEStudioCore, Logging
Logging.disable_logging(Logging.Warn)

nested_solver(p) = create_sim_data([0.0], [only(p[:value]) === nothing ? 10.0 : 20.0], p)
tag_solver(p) = create_sim_data([0.0], [typeof(p[:value]).parameters[1] === reinterpret(Float64, UInt64(0x7ff8000000000001)) ? 10.0 : 20.0], p)

function compare_cache(label, solver, a, b)
    mktempdir() do root
        set_save_path!(root)
        params(v) = create_param_dict(:sim_func_name => solver, :value => v)
        x, y = params(a), params(b)
        println(label, ": normalized ", repr(get_clean_params(x)[:value]), " / ", repr(get_clean_params(y)[:value]),
                "; hash equal=", calculate_hash(x) == calculate_hash(y))
        run_all_simulations(SimulationConfig(x))
        s = run_all_simulations(SimulationConfig(y))
        println(label, ": second cached=", length(s.cached), " field=", load_sim_data(y).u[1][1])
        run_all_simulations(SimulationConfig(y); force_overwrite = true)
        println(label, ": second forced field=", load_sim_data(y).u[1][1])
    end
end

for (a, b) in ((nothing, Nothing), (missing, Missing))
    x, y = create_param_dict(:v => a), create_param_dict(:v => b)
    println("Top level ", repr(a), "/", repr(b), ": same hash=", calculate_hash(x) == calculate_hash(y))
    x, y = create_param_dict(:v => Any[a]), create_param_dict(:v => Any[b])
    println("Nested ", repr(a), "/", repr(b), ": same hash=", calculate_hash(x) == calculate_hash(y))
end
compare_cache("Nested nothing", :nested_solver, Any[nothing], Any[Nothing])

a, b = map(x -> reinterpret(Float64, x), (0x7ff8000000000001, 0x7ff8000000000002))
x, y = Val{a}(), Val{b}()
println("Val NaN types distinct=", typeof(x) !== typeof(y))
compare_cache("Val NaN payload", :tag_solver, x, y)
