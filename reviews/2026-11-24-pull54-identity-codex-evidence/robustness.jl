using PDEStudioCore, Logging

struct DirectNames
    mode::Int
end
struct NestedNames
    mode::Int
end
function names_for_mode(mode)
    return mode == 1 ? (; left = 1, right = 2) : NamedTuple{(Symbol("left=1, right"),)}((2,))
end
PDEStudioCore.param_identity(v::DirectNames) = names_for_mode(v.mode)
PDEStudioCore.param_identity(v::NestedNames) = (; detail = names_for_mode(v.mode))

struct PrivateField
    visible::Int
    stored::Int
end
Base.propertynames(::PrivateField) = (:visible,)
PDEStudioCore.@param_struct PrivateField
struct KeyWithWorkspace
    workspace::Int
    id::Int
end
PDEStudioCore.param_identity(v::KeyWithWorkspace) = (; id = v.id)

PDEStudioCore.@param_struct struct LabelMap
    labels::Dict{String, Int}
end

mode_solver(p) = create_sim_data([0.0], [10.0 * p[:v].mode], p)
label_solver(p) = create_sim_data([0.0], [3.0], p)

function run_pair(label, a, b)
    mktempdir() do root
        set_save_path!(root)
        for v in (a, b)
            p = create_param_dict(:sim_func_name => :mode_solver, :v => v)
            try
                s = run_all_simulations(SimulationConfig(p))
                d = load_sim_data(p)
                println(label, ": hash=", calculate_hash(p), " stored=", repr(d.params[:v]),
                        " ran=", length(s.ran), " cached=", length(s.cached), " field=", only(only(d.u)))
            catch e
                e isa ArgumentError || rethrow()
                println(label, ": ", sprint(showerror, e))
            end
        end
    end
end

hash_value(v) = calculate_hash(ParamDict(:v => v))

function check_dicts()
    a = Dict(KeyWithWorkspace(9, 1) => "low", KeyWithWorkspace(0, 2) => "high")
    b = Dict(KeyWithWorkspace(0, 1) => "low", KeyWithWorkspace(9, 2) => "high")
    println("Identical declared key pairs: hashes_match=", hash_value(a) == hash_value(b))
    c = Dict(KeyWithWorkspace(0, 1) => "low", KeyWithWorkspace(9, 1) => "high")
    try
        println("Duplicate declared dictionary key: accepted hash=", hash_value(c))
    catch e
        e isa ArgumentError || rethrow()
        println("Duplicate declared dictionary key: ", sprint(showerror, e))
    end
end

function check_filter()
    mktempdir() do root
        set_save_path!(root)
        save_sim_data(create_sim_data([0.0], [1.0], ParamDict(:value => "Closure")); verbose = false)
        try
            result = delete_sim_data(ParamDict(:value => sin); dry_run = true)
            println("Function filter: preview_matches=", length(result))
        catch e
            e isa ArgumentError || rethrow()
            println("Function filter: ", sprint(showerror, e))
        end
    end
end

function check_single_pass_import_filter()
    mktempdir() do root
        set_save_path!(joinpath(root, "source"))
        p = ParamDict(:value => "skip")
        src = save_sim_data(create_sim_data([0.0], [1.0], p); verbose = false)
        set_save_path!(joinpath(root, "destination"))
        filter = Iterators.Stateful([:value => "keep"])
        imported = import_sim_data(src; filter_pairs = filter)
        println("Single-pass mismatch filter: imported=", length(imported), " present=", does_sim_data_exist(p))
    end
end

function check_old_cache(action, root)
    set_save_path!(root)
    labels = Dict("phase\tA" => 1, "phase0" => 2)
    p = create_param_dict(:sim_func_name => :label_solver, :v => LabelMap(labels))
    println("Plain dictionary control: hash=", hash_value(labels))
    println("Declared LabelMap: hash=", calculate_hash(p), " stored=", repr(get_clean_params(p)[:v]))
    if action == "prepare"
        s = run_all_simulations(SimulationConfig(p))
        println("Prepare: ran=", length(s.ran), " stored=", length(find_sim_data(; verbose = false)))
    elseif action == "read"
        println("Lookup of identical inputs before running: exists=", does_sim_data_exist(p))
        s = run_all_simulations(SimulationConfig(p))
        println("Read: ran=", length(s.ran), " cached=", length(s.cached),
                " stored=", length(find_sim_data(; verbose = false)))
    end
end

with_logger(NullLogger()) do
    if isempty(ARGS)
        run_pair("Direct names", DirectNames(1), DirectNames(2))
        run_pair("Nested names", NestedNames(1), NestedNames(2))
        println("Hidden stored field: hashes_differ=", hash_value(PrivateField(1, 1)) != hash_value(PrivateField(1, 2)))
        check_dicts()
        check_filter()
        check_single_pass_import_filter()
    else
        check_old_cache(ARGS...)
    end
end
