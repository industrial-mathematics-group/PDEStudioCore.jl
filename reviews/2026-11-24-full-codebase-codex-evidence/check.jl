using PDEStudioCore, Logging

case_params(k) = create_param_dict(:sim_func_name => :review_solver, :k => k)
review_solver(p) = create_sim_data([0.0, 1.0], fill(Float64(p[:k]), 2), p)
review_reference(p) = _ -> p[:k]
function review_postprocess(data)
    data.params[:k] = 2
    return true
end

function postprocess_destination()
    set_save_path!(mktempdir())
    a, b = case_params(1), case_params(2)
    save_sim_data(review_solver(b))
    before = only(unique(first.(load_sim_data(b).u)))
    result = run_all_simulations(SimulationConfig(a; postprocess=:review_postprocess))
    println("postprocess only k=1: outcomes=", result.postprocessing,
            " k=2 before=", before, " after=", first(load_sim_data(b).u)[1],
            " k=1 has completion record=", haskey(load_sim_data(a).metadata, :postprocessed))
end

function changed_import_parameters()
    set_save_path!(mktempdir())
    a, b = case_params(1), case_params(2)
    cfg(p) = SimulationConfig(p; reference=:review_reference)
    set_stat_registry!(Dict(:l1error => :time))
    run_all_simulations(cfg(a); calculate_stats=true)
    source = get_file_name(a)
    set_save_path!(mktempdir())
    imports = mktemp() do _, io
        write(io, "2\n")
        seekstart(io)
        redirect_stdin(io) do
            redirect_stdout(devnull) do
                import_sim_data(source; prompt_keys=[:k])
            end
        end
    end
    normal = run_all_simulations(cfg(b); calculate_stats=true)
    stored = load_sim_data(b).stats[:l1error][1]
    run_all_simulations(cfg(b); calculate_stats=true, force_stats=true)
    println("edited import k=1 -> k=2: imports=", length(imports), " stats=", normal.stats,
            " stored L1 error=", stored, " recomputed=", load_sim_data(b).stats[:l1error][1])
end

function finite_statistics()
    set_stat_registry!(Dict(:mass => :time, :l2norm => :time))
    for T in (Float16, Float64)
        d = create_sim_data(T[-40000, 0, 40000], T[0.25, 0.25, 0.25], ParamDict())
        calculate_all_stats!(d; save=false)
        println("wide grid ", T, ": spacing=", Float64(d.domain.spacing[1]), " mass=", Float64(d.stats[:mass][1]))
        d = create_sim_data(T[0, 1], T[300, 300], ParamDict())
        calculate_all_stats!(d; save=false)
        println("unit spacing ", T, ": L2 norm=", Float64(d.stats[:l2norm][1]))
    end
end

with_logger(NullLogger()) do
    println("Julia ", VERSION)
    set_stat_preset!("hyperbolic")
    Base.invokelatest(postprocess_destination)
    Base.invokelatest(changed_import_parameters)
    Base.invokelatest(finite_statistics)
end
