using PDEStudioCore, StaticArrays, Logging

function exact_cases()
    set_save_path!(mktempdir())
    set_stat_preset!("hyperbolic")
    set_stat_registry!(Dict(:mass => :time))
    d = DomainInfo{1,Int}((:x,), (0,), (1,), (1,), nothing)
    vals = [2^53 + 1, -2^53]
    field = ESimData(ParamDict(), d, ([0,1],), SVector.(vals))
    calculate_all_stats!(field, _ -> 0; save=false)
    println("integer cancellation: exact sum=", sum(vals), " mass=", field.stats[:mass][1])
    T = Rational{Int}
    lo = 10^16 // 1
    hi = lo + 1
    bounds = DomainInfo{1,T}((:x,), (lo,), (hi,), (1//1,), nothing)
    result = try
        ref = generate_reference_simdata(_ -> 1//1, ParamDict(), bounds, (2,), :eulerian)
        (axis_step=ref.axes[1][2] - ref.axes[1][1], stored_spacing=only(ref.domain.spacing))
    catch e
        typeof(e)
    end
    println("rational reference with offset 10^16: ", result)
end

with_logger(NullLogger()) do
    exact_cases()
end
