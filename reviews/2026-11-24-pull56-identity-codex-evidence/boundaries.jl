using PDEStudioCore, Logging

struct KeyWithWork
    work::Int
    id::Int
end
PDEStudioCore.param_identity(k::KeyWithWork) = (; id = k.id)

struct WithDetail{T}
    detail::T
end
PDEStudioCore.param_identity(x::WithDetail) = (; detail = x.detail)

struct MixedLabels
    labels::Dict{Any, Int}
end
PDEStudioCore.@param_struct MixedLabels

unit_solver(p) = create_sim_data([0.0], [1.0], p)

function check_pair(label, a, b; run = false)
    p = ParamDict(:sim_func_name => :unit_solver, :v => a)
    q = ParamDict(:sim_func_name => :unit_solver, :v => b)
    same = calculate_hash(p) == calculate_hash(q)
    println(label, ": hashes_match=", same)
    if run
        println("  first stored form=", repr(get_clean_params(p)[:v]))
        println("  second stored form=", repr(get_clean_params(q)[:v]))
        mktempdir() do root
            set_save_path!(root)
            first_run = run_all_simulations(SimulationConfig(p))
            second_run = run_all_simulations(SimulationConfig(q))
            println("  first ran=", length(first_run.ran), " second ran=", length(second_run.ran),
                    " second cached=", length(second_run.cached), " stored files=", length(find_sim_data(; verbose = false)))
        end
    end
end

function check_key_positions()
    for (name, wrap) in (("direct key", identity), ("tuple key", x -> (x, 0)), ("pair key", x -> x => 0),
                         ("vector key", x -> [x]), ("tuple containing a vector key", x -> ([x], 0)))
        a = Dict(wrap(KeyWithWork(9, 1)) => "low", wrap(KeyWithWork(0, 2)) => "high")
        b = Dict(wrap(KeyWithWork(0, 1)) => "low", wrap(KeyWithWork(9, 2)) => "high")
        check_pair(name, a, b; run = name == "vector key")
    end
end

function check_equal_sort_keys()
    for i in 1:4096
        word = "label_$i"
        label = Symbol(word)
        a = Dict{Any, Int}(word => 10, label => 20)
        b = Dict{Any, Int}(label => 20, word => 10)
        isequal(collect(keys(a)), collect(keys(b))) && continue
        println("Mixed keys: equal dictionaries=", isequal(a, b), " and equal raw sort keys=", string(label) == string(word))
        check_pair("Mixed keys in a declared identity", MixedLabels(a), MixedLabels(b); run = true)
        return
    end
    error("no mixed pair with different iteration orders found")
end

function check_named_tuple_filters()
    t = (; x = 1)
    for (label, v) in (("top level", t), ("declared field", WithDetail(t)), ("array element", [t]),
                      ("dictionary key", Dict(t => 1)), ("dictionary value", Dict(:a => t)),
                      ("pair value", :a => t), ("set element", Set([t])), ("tuple element", (t,)))
        try
            println("Named tuple ", label, ": accepted hash=", calculate_hash(ParamDict(:v => v)))
        catch e
            e isa ArgumentError || rethrow()
            println("Named tuple ", label, ": ", sprint(showerror, e))
        end
    end
    println("Ordinary declared identity: stored=", repr(get_clean_params(ParamDict(:v => WithDetail(Dict(:x => 1))))[:v]))
end

function check_multi_file_filter()
    mktempdir() do root
        source = joinpath(root, "source")
        set_save_path!(source)
        for mode in ("keep", "skip")
            p = ParamDict(:mode => mode)
            save_sim_data(create_sim_data([0.0], [1.0], p); verbose = false)
        end
        set_save_path!(joinpath(root, "destination"))
        result = import_sim_data(joinpath(source, "data"); filter_pairs = Iterators.Stateful([:mode => "keep"]))
        println("One-pass filter, two files: imported=", length(result), " kept=", does_sim_data_exist(ParamDict(:mode => "keep")),
                " skipped file present=", does_sim_data_exist(ParamDict(:mode => "skip")))
    end
end

with_logger(NullLogger()) do
    check_named_tuple_filters()
    check_key_positions()
    check_equal_sort_keys()
    check_multi_file_filter()
end
