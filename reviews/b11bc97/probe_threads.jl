# Prints a digest of results that touch threaded code; run with -t 1 and -t 4 and compare.
using PDEStudioCore, StaticArrays, SHA, Random
PDEStudioCore.set_target_module!(@__MODULE__)
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())
register_stat!(:field_err, :all)
PDEStudioCore.calc_stat(::Val{:field_err}, fc, u, ana, domain::DomainInfo) = first(u) - first(ana)
register_stat!(:xprof, :x)
PDEStudioCore.calc_stat(::Val{:xprof}, fc, u, ana, domain::DomainInfo) = sum(u) * get_integration_measure(:xprof, domain)

digest(x) = bytes2hex(sha256(repr(x)))[1:16]
out = String[]
rng = Xoshiro(1)
# Eulerian 2D + time, Float64 and Float32
for T in (Float64, Float32)
    x = sort(rand(rng, T, 37)); y = collect(T, range(0, 2, length = 23)); t = collect(T, range(0, 1, length = 11))
    u = [SVector{2, T}(sin(xi + ti) * yi, cos(xi * yi) + ti) for xi in x, yi in y, ti in t]
    d = create_sim_data((x, y), u, t, create_param_dict(:case => "thr", :T => string(T)))
    ref = p -> SVector{2, T}(sin(p[1] + p[3]) * p[2], cos(p[1] * p[2]))
    calculate_all_stats!(d, ref; save = false)
    push!(out, "E $T stats " * digest(sort!(collect(pairs(copy(d.stats))), by = first)))
    r = resample_eulerian(d, (50, 17, 7))
    push!(out, "E $T resample " * digest((r.u, sort!(collect(pairs(copy(r.stats))), by = first))))
    L = convert_to_lagrangian(d)
    push!(out, "E->L $T " * digest((L.u, sort!(collect(pairs(copy(L.stats))), by = first))))
    g = generate_reference_simdata(ref, d.params, d.domain, (13, 9, 5), :eulerian)
    gl = generate_reference_simdata(ref, d.params, d.domain, (13, 9, 5), :lagrangian)
    push!(out, "ref $T " * digest((g.u, gl.u)))
    # Lagrangian with varying particle counts and NaN positions
    xs = [[SVector{2, T}(rand(rng, T), 2rand(rng, T)) for _ in 1:(200 + 10n)] for n in 1:9]
    xs[3][5] = SVector{2, T}(NaN, 0)
    us = [[SVector{2, T}(p[1], p[2]^2) for p in step] for step in xs]
    Ld = create_sim_data(xs, us, collect(T, range(0, 1, length = 9)), create_param_dict(:case => "thrL", :T => string(T)))
    calculate_all_stats!(Ld, ref; save = false)
    push!(out, "L $T stats " * digest(sort!(collect(pairs(copy(Ld.stats))), by = first)))
    E = convert_to_eulerian(Ld, (31, 19, 6))
    push!(out, "L->E $T " * digest((E.u, sort!(collect(pairs(copy(E.stats))), by = first))))
end
foreach(println, out)
