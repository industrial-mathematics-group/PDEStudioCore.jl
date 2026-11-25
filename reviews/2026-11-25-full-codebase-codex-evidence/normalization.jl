using PDEStudioCore
using Logging
Logging.disable_logging(Logging.Warn)

println("Julia ", VERSION)
a = Set{Any}([:abel, "abel"])
b = Set{Any}(["abel", :abel])
p(v) = create_param_dict(:set => v)
println("Equal mixed sets: ", isequal(a, b), " same hash=", calculate_hash(p(a)) == calculate_hash(p(b)))
println("Small mixed set A: ", val2str(a))
println("Small mixed set B: ", val2str(b))
items = Any[v for i in 1:50 for v in ("label_$i", Symbol("label_$i"))]
x, y = Set{Any}(items), Set{Any}(reverse(items))
println("Equal mixed sets of 100 values: ", isequal(x, y), " same hash=", calculate_hash(p(x)) == calculate_hash(p(y)))
println("Mixed set hash A: ", calculate_hash(p(x)))
println("Mixed set hash B: ", calculate_hash(p(y)))

for (label, value) in (
    ("large floating value", 1.5e0),
    ("small BigInt", big(1)),
    ("small UInt64", UInt64(1)),
    ("small Int128", Int128(1)),
    ("plain Int64", Int64(1)),
    ("one Float64", 1.0),
)
    native = get_clean_params(p(value))[:set]
    println(label, ": ", typeof(value), " -> ", typeof(native), " ", repr(native), " same hash as Int64(1)=",
            calculate_hash(p(value)) == calculate_hash(p(Int64(1))))
end

set_solver(p) = create_sim_data([0., 1.], fill(Float64(length(p[:set])), 2), p)
signedness_solver(p) = create_sim_data([0., 1.], fill(p[:value] isa UInt64 ? 20. : 10., 2), p)

mktempdir() do root
    set_save_path!(root)
    for (label, value) in (("original order", x), ("reverse order", y))
        params = create_param_dict(:sim_func_name => :set_solver, :set => value)
        result = run_all_simulations(SimulationConfig(params))
        println("Equal set, ", label, ": ran=", length(result.ran), " cached=", length(result.cached),
                " files=", length(find_sim_data(; verbose = false)))
    end
end
mktempdir() do root
    set_save_path!(root)
    for value in (Int64(1), UInt64(1))
        params = create_param_dict(:sim_func_name => :signedness_solver, :value => value)
        result = run_all_simulations(SimulationConfig(params))
        println(typeof(value), ": cached=", length(result.cached), " field=", load_sim_data(params).u[1][1])
    end
    params = create_param_dict(:sim_func_name => :signedness_solver, :value => UInt64(1))
    run_all_simulations(SimulationConfig(params); force_overwrite = true)
    println("UInt64 forced result: ", load_sim_data(params).u[1][1])
end
