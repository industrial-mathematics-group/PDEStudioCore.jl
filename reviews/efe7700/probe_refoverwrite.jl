# Probe: a reference dataset at the native resolution replaces the native data on disk
using Test, PDEStudioCore, StaticArrays, Logging
global_logger(ConsoleLogger(stderr, Logging.Warn))
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())
@testset "reference at native resolution" begin
    p = create_param_dict(:tag => "native-res", :N => 20)
    x = collect(range(0.0, 1.0, length = 20)); t = collect(range(0.0, 1.0, length = 5))
    sim = create_sim_data(x, [SVector(1.0 + xi) for xi in x, _ in t], t, p)     # "numerical" result
    exact(xt) = SVector(sin(xt[1]))                                            # something else
    calculate_all_stats!(sim, exact)                                           # saved
    ref = generate_reference_simdata(exact, p, sim.domain, size(sim.u), :eulerian)
    calculate_all_stats!(ref, exact)                                           # default save = true, no warning
    on_disk = load_sim_data(p)
    @show on_disk.u[3, 2] sim.u[3, 2]
    @test on_disk.u == ref.u && on_disk.u != sim.u                             # native data replaced by the reference
    # the same holds for a Lagrangian round trip of Lagrangian-native data, and for convert_to_lagrangian of
    # Eulerian data whose particle count happens to equal (nt, N)
end
