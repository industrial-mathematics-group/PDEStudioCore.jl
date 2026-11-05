# Probe: results must not depend on the thread count. Run with -t 1 and -t 4 and compare the printed digests.
using PDEStudioCore, StaticArrays, SHA, Logging
using PDEStudioCore.Examples: solve_heat_2d, exact_heat_2d, solve_particles_2d, exact_particles_2d
global_logger(ConsoleLogger(stderr, Logging.Warn))
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())
digest(x) = bytes2hex(sha256(repr(x)))[1:16]
out = String[]
c = test_heat_2d()
p = merge(copy(c.shared), c.methods[:adi], Dict{Symbol,Any}(:r => 0.3))
e = solve_heat_2d(p)
calculate_all_stats!(e, exact_heat_2d(p); save = false)
for k in sort!(collect(keys(e.stats))); push!(out, "E $k $(digest(e.stats[k]))"); end
cp = test_particles_2d()
q = merge(copy(cp.shared), cp.methods[:rk4], Dict{Symbol,Any}(:K => 30))
l = solve_particles_2d(q)
calculate_all_stats!(l, exact_particles_2d(q); save = false)
for k in sort!(collect(keys(l.stats))); push!(out, "L $k $(digest(l.stats[k]))"); end
E = convert_to_eulerian(l, (25, 25, 13))
push!(out, "scatter $(digest(E.u))")
R = resample_eulerian(e, (17, 23, 9))
push!(out, "resample $(digest(R.u))")
ref = generate_reference_simdata(exact_heat_2d(p), p, e.domain, (11, 11, 5), :eulerian)
push!(out, "refE $(digest(ref.u))")
refL = generate_reference_simdata(exact_particles_2d(q), q, l.domain, (7, 7, 4), :lagrangian)
push!(out, "refL $(digest(refL.u))")
println("nthreads=$(Threads.nthreads())")
foreach(println, out)
