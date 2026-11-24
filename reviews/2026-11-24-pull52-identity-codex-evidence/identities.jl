using PDEStudioCore, Logging

const HAS_IDENTITY = isdefined(PDEStudioCore, :param_identity)

module ∇Review
struct Tags{K} end
end

struct DomainSpec{F}
    id::Int
    boundary::F
    work::Int
end
struct Delimiters
    mode::Int
end
struct BoundaryKey
    work::Int
    id::Int
end
struct HiddenField
    public_value::Int
    hidden_value::Int
end
Base.propertynames(::HiddenField, private::Bool = false) = private ? (:public_value, :hidden_value) : (:public_value,)

struct Undeclared
    id::Int
end
struct BadIdentity
    id::Int
end
struct FunctionIdentity{F}
    f::F
end

if HAS_IDENTITY
    @eval begin
        PDEStudioCore.param_identity(d::DomainSpec) = (; id = d.id)
        PDEStudioCore.param_identity(d::Delimiters) = d.mode == 1 ?
            (; left = 1, right = 2) : NamedTuple{(Symbol("left=1, right"),)}((2,))
        PDEStudioCore.param_identity(k::BoundaryKey) = (; id = k.id)
        PDEStudioCore.@param_struct HiddenField
        PDEStudioCore.param_identity(x::BadIdentity) = x.id
        PDEStudioCore.param_identity(x::FunctionIdentity) = (; function_value = x.f)
        PDEStudioCore.@param_struct ∇Review.Tags
    end
end

if "visible" in ARGS
    using .∇Review: Tags
end

function run_pair(label, solver, a, b)
    mktempdir() do root
        set_save_path!(root)
        for v in (a, b)
            p = create_param_dict(:sim_func_name => solver, :value => v)
            s = run_all_simulations(SimulationConfig(p))
            d = load_sim_data(p)
            println(label, ": stored=", repr(get_clean_params(p)[:value]), " hash=", calculate_hash(p),
                    " ran=", length(s.ran), " cached=", length(s.cached), " field=", first(first(d.u)))
        end
    end
end

delimiters_solver(p) = create_sim_data([0.0], [10.0 * p[:value].mode], p)
hidden_solver(p) = create_sim_data([0.0], [10.0 * getfield(p[:value], :hidden_value)], p)
hash_value(v) = calculate_hash(ParamDict(:value => v))

function print_rejection(label, value)
    try
        println(label, ": accepted as ", repr(get_clean_params(ParamDict(:value => value))[:value]))
    catch e
        println(label, ": ", sprint(showerror, e))
    end
end

function check_dict_order()
    first_order = Dict(BoundaryKey(9, 1) => "low", BoundaryKey(0, 2) => "high")
    second_order = Dict(BoundaryKey(0, 1) => "low", BoundaryKey(9, 2) => "high")
    for d in (first_order, second_order)
        println("Dictionary keys: stored=", repr(get_clean_params(ParamDict(:value => d))[:value]), " hash=", hash_value(d))
    end
end

with_logger(NullLogger()) do
    if HAS_IDENTITY
        a = DomainSpec(1, sin, 1)
        b = DomainSpec(1, cos, 99)
        c = DomainSpec(2, sin, 1)
        println("Declared domain: ignores callbacks and working fields=", hash_value(a) == hash_value(b),
                " changes when id changes=", hash_value(a) != hash_value(c),
                " stable after normalization=", hash_value(a) == calculate_hash(get_clean_params(ParamDict(:value => a))))
        println("Module import check: tag=", repr(val2str(∇Review.Tags{:minmod}())), " hash=", hash_value(∇Review.Tags{:minmod}()))
    end
    print_rejection("Nested undeclared", (; data = Any[Undeclared(1)]))
    print_rejection("Wrong return type", BadIdentity(1))
    print_rejection("Function returned by identity", FunctionIdentity(sin))
    run_pair("Distinct identity names", :delimiters_solver, Delimiters(1), Delimiters(2))
    run_pair("All fields macro", :hidden_solver, HiddenField(1, 1), HiddenField(1, 2))
    check_dict_order()
    mktempdir() do root
        set_save_path!(root)
        save_sim_data(create_sim_data([0.0], [1.0], ParamDict(:value => "Closure")); verbose = false)
        println("Function used as delete filter: preview_matches=", length(delete_sim_data(ParamDict(:value => sin); dry_run = true)))
    end
end
