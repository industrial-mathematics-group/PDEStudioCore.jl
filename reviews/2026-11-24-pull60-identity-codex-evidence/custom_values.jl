using PDEStudioCore, Logging

struct CodingChoice <: Integer
    code::Int
    variant::Symbol
end
Base.string(v::CodingChoice) = string(v.code)
PDEStudioCore.param_identity(v::CodingChoice) = (; code = v.code, variant = v.variant)

function variant_solver(p)
    value = p[:choice].variant === :left ? 10.0 : 20.0
    return create_sim_data([0.0], [value], p)
end

with_logger(NullLogger()) do
    mktempdir() do root
        set_save_path!(root)
        for variant in (:left, :right)
            p = ParamDict(:sim_func_name => :variant_solver, :choice => CodingChoice(2, variant))
            s = run_all_simulations(SimulationConfig(p))
            d = load_sim_data(p)
            println("Custom Integer value: variant=", variant, " declared=", param_identity(p[:choice]),
                    " stored=", repr(d.params[:choice]), " hash=", calculate_hash(p),
                    " ran=", length(s.ran), " cached=", length(s.cached), " field=", only(only(d.u)))
        end
    end
end
