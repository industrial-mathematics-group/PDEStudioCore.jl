using PDEStudioCore, Logging

struct CompatibleLimiter
    order::Int
end
struct SourcedLimiter
    order::Int
end

if isdefined(PDEStudioCore, :param_identity)
    @eval PDEStudioCore.@param_struct CompatibleLimiter
end

sourced_solver(p) = create_sim_data([0.0], [Float64(p[:limiter].order)], p)

function check_source_declaration()
    mktempdir() do root
        set_save_path!(root)
        source = joinpath(root, "identity.jl")
        write(source, "PDEStudioCore.param_identity(x::SourcedLimiter) = (; order = x.order)\n")
        p = create_param_dict(:sim_func_name => :sourced_solver, :limiter => SourcedLimiter(3))
        config = SimulationConfig(p; sources = [source])
        try
            summary = run_all_simulations(config)
            println("Identity declared by config.sources: ran=", length(summary.ran))
        catch e
            e isa ArgumentError || rethrow()
            println("Identity declared by config.sources: ", sprint(showerror, e))
            println("Method exists in the latest world=", Base.invokelatest(hasmethod, PDEStudioCore.param_identity, Tuple{SourcedLimiter}))
            retry = Base.invokelatest(run_all_simulations, config; load_sources = false)
            data = Base.invokelatest(load_sim_data, p)
            println("Latest-world retry: ran=", length(retry.ran), " field=", only(only(data.u)))
        end
    end
end

action, root = ARGS
with_logger(NullLogger()) do
    set_save_path!(root)
    p = create_param_dict(:limiter => CompatibleLimiter(3))
    if action == "prepare"
        path = save_sim_data(create_sim_data([0.0], [3.0], p); verbose = false)
        println("First parent stored ", basename(path))
    elseif action == "read"
        println("Head found ", basename(get_file_name(p)), " field=", only(only(load_sim_data(p).u)))
        check_source_declaration()
    end
end
