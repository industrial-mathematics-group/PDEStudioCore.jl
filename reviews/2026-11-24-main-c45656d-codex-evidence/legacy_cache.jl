using PDEStudioCore, Logging

legacy_unit_field(p) = create_sim_data([0.0, 1.0], [1.0, 1.0], p)

action, root = ARGS
set_save_path!(joinpath(root, "results"))
reference_file = joinpath(root, "reference.jl")
set_reference(value) = write(reference_file, "legacy_reference(p) = _ -> $value\n")
params = create_param_dict(:sim_func_name => :legacy_unit_field)
function report(label; kwargs...)
    Base.include(Main, reference_file)
    cfg = SimulationConfig(params; reference = :legacy_reference)
    summary = Base.invokelatest(run_all_simulations, cfg; calculate_stats = true, kwargs...)
    d = load_sim_data(params)
    println(label, ": stats=", only(keys(summary.stats)), " L1=", only(d.stats[:l1error]),
            " L2=", haskey(d.stats, :l2error) ? only(d.stats[:l2error]) : missing)
end

with_logger(NullLogger()) do
    set_stat_preset!("hyperbolic")
    set_stat_registry!(Dict(:l1error => :time))
    if action == "prepare"
        set_reference(2.0)
        report("First parent A")
        set_reference(4.0)
        register_stat!(:l2error, :time)
        report("First parent B plus L2")
        set_reference(2.0)
    elseif action == "check"
        register_stat!(:l2error, :time)
        report("Head with restored legacy A"; on_changed_sources = :recompute)
        report("Head after force_stats"; force_stats = true)
    end
end
