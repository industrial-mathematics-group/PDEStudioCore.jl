using PDEStudioCore
set_stat_preset!("hyperbolic")
set_stat_registry!(Dict(:l2norm => :time))
x = [0.0, 1e200]
t = collect(0.0:31.0)
data = create_sim_data((x, x), ones(2, 2, length(t)), t, ParamDict())
println("threads=", Threads.nthreads(), " slices=", length(t), " spacings=", data.domain.spacing)
flush(stdout)
try
    calculate_all_stats!(data; save = false)
    println("returned; first L2=", first(data.stats[:l2norm]))
catch err
    println("caught ", typeof(err), ": ", sprint(showerror, err))
end
