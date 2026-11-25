using PDEStudioCore
using Logging
Logging.disable_logging(Logging.Warn)

contract_solver(p) = create_sim_data([0., 1.], ones(2), p)
contract_reference(p) = _ -> 3.0
PDEStudioCore.calc_stat(::Val{:aux}, coords, u, ref, domain) = first(u)
PDEStudioCore.calc_stat(::Val{:fallback}, coords, u, ref, domain) =
    any(v -> isnan(v[1]), ref) ? first(u) : first(ref)

function records(p)
    PDEStudioCore.JLD2.jldopen(get_file_name(p), "r") do file
        [k => (haskey(file, k) ? file[k] : missing)
         for k in ("evaluated_stats", "evaluated_with_reference", "evaluated_reference")]
    end
end

p = create_param_dict(:sim_func_name => :contract_solver)
for deletion in (:none, :stats_view, :whole_stat)
    mktempdir() do root
        set_save_path!(root)
        set_stat_registry!(Dict(:aux => Symbol[]))
        config = SimulationConfig(p; reference = :contract_reference)
        run_all_simulations(config; calculate_stats = true)
        d = load_sim_data(p)
        deletion === :stats_view && delete!(d.stats, :aux)
        deletion === :whole_stat && delete_stat!(d, :aux)
        d.metadata[:quality_control] = "reviewed"
        save_sim_data(d; overwrite = true, verbose = false)
        println("After save ", deletion, ": has aux=", haskey(load_sim_data(p).stats, :aux), " records=", records(p))
        summary = run_all_simulations(config; calculate_stats = true)
        println("After pipeline ", deletion, ": ", summary.stats, " has aux=", haskey(load_sim_data(p).stats, :aux))
        run_all_simulations(config; calculate_stats = true, force_stats = true)
        println("After forcing ", deletion, ": aux=", load_sim_data(p).stats[:aux][1])
    end
end

mktempdir() do root
    set_save_path!(root)
    set_stat_registry!(Dict(:aux => Symbol[]))
    c = SimulationConfig(p; reference = :contract_reference)
    run_all_simulations(c; calculate_stats = true)
    c.reference = nothing
    register_stat!(:fallback, Symbol[])
    run_all_simulations(c; calculate_stats = true)
    println("A then no reference: fallback=", load_sim_data(p).stats[:fallback][1], " records=", records(p))
    c.reference = :contract_reference
    summary = run_all_simulations(c; calculate_stats = true)
    println("Restore same A: ", summary.stats, " fallback=", load_sim_data(p).stats[:fallback][1])
    run_all_simulations(c; calculate_stats = true, force_stats = true)
    println("Restore same A forced: fallback=", load_sim_data(p).stats[:fallback][1])
end

mktempdir() do root
    set_save_path!(root)
    set_stat_registry!(Dict(:fallback => Symbol[]))
    c = SimulationConfig(p)
    run_all_simulations(c; calculate_stats = true)
    println("Fresh no reference: fallback=", load_sim_data(p).stats[:fallback][1])
    c.reference = :contract_reference
    summary = run_all_simulations(c; calculate_stats = true)
    println("Fresh then A: ", summary.stats, " fallback=", load_sim_data(p).stats[:fallback][1])

    data = create_sim_data([0., 1.], [4., 4.], p)
    save_sim_data(data; overwrite = true, verbose = false)
    println("Replacing solution: records=", records(p))
end
