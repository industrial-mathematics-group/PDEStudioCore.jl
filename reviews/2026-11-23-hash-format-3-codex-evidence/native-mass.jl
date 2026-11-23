using PDEStudioCore, StaticArrays, Logging

with_logger(NullLogger()) do
    set_stat_preset!("hyperbolic")
    set_stat_registry!(Dict(:mass=>:time))
    for T in (Float16, Float32)
        d = create_sim_data(SVector.(T[-40000,40000]), fill(T(0.25), 2), ParamDict())
        calculate_all_stats!(d; save=false)
        println("format=",PDEStudioCore._HASH_FORMAT," type=",T," spacing=",Float64(only(d.domain.spacing)),
                " native mass=",Float64(only(d.stats[:mass]))," expected=20000")
    end
end
