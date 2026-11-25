using PDEStudioCore, Logging
Logging.disable_logging(Logging.Warn)

struct NumericChoice <: Integer
    value::Int64
    variant::Symbol
end
Base.show(io::IO, x::NumericChoice) = print(io, x.value)
Base.string(x::NumericChoice) = string(x.value)
PDEStudioCore.param_identity(x::NumericChoice) = (; value = x.value, variant = x.variant)

struct CharChoice <: AbstractChar
    variant::Symbol
end
Base.show(io::IO, ::CharChoice) = print(io, "'a'")
PDEStudioCore.param_identity(x::CharChoice) = (; variant = x.variant)
char_solver(p) = create_sim_data([0.0], [p[:x].variant === :left ? 10.0 : 20.0], p)
boundary_solver(p) = create_sim_data([0.0], [1.0], p)
const SV = PDEStudioCore.StaticArrays.SVector

function attempt(label, f)
    try
        println(label, ": ", f())
    catch e
        e isa ArgumentError || rethrow()
        println(label, ": ", sprint(showerror, e))
    end
end

mktempdir() do root
    set_save_path!(root)
    for (label, value) in (("Int64 endpoints", (typemin(Int64), typemax(Int64))),
                           ("Float32 and Float16", (1.5f0, Float16(2.0))),
                           ("Other scalar width", UInt64(1)),
                           ("Declared custom integer", NumericChoice(1, :a)),
                           ("Tuple nested BigInt", (:x, [big(1)])),
                           ("Static array Int32", [SV(Int32(1))]),
                           ("Int32 range as a value", Int32(1):Int32(3)),
                           ("Set behind a pair", :label => Set(Any["x", :x])),
                           ("Int64 map", Dict(typemin(Int64) => 0, typemax(Int64) => 1)),
                           ("Int32 map", Dict(Int32(1) => 0)))
        attempt(label, () -> begin
            p = create_param_dict(:sim_func_name => :boundary_solver, :x => value)
            s = run_all_simulations(SimulationConfig(p))
            normalized = get_clean_params(p)[:x]
            isempty(s.failed) || error(last(only(s.failed)))
            "accepted, stored type $(typeof(normalized)), lookup $(does_sim_data_exist(p))"
        end)
    end
    p = create_param_dict(:sim_func_name => :boundary_solver, :x => 1.5)
    for values in (Any[1.5f0, 1.5], Any[1.5f0, 1.5f0], Any[Float32[1.5], Float64[1.5]])
        label = "Sweep $(repr(values))"
        attempt(label, () -> length(generate_tasks(SimulationConfig(p; varied = Dict(:x => values)))))
    end
end

mktempdir() do root
    set_save_path!(root)
    for variant in (:left, :right)
        x = CharChoice(variant)
        p = create_param_dict(:sim_func_name => :char_solver, :x => x)
        println("Character declared identity ", param_identity(x), " normalizes to ", repr(get_clean_params(p)[:x]))
        s = run_all_simulations(SimulationConfig(p))
        println("Character ", variant, ": cached=", length(s.cached), " field=", load_sim_data(p).u[1][1])
        if variant === :right
            run_all_simulations(SimulationConfig(p); force_overwrite = true)
            println("Character right forced: field=", load_sim_data(p).u[1][1])
        end
    end
end
