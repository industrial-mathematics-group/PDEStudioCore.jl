using Test, PDEStudioCore, StaticArrays
PDEStudioCore.set_target_module!(@__MODULE__)
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())

function const_solver(params)
    x = collect(range(0.0, 1.0, length = 5))
    return create_sim_data(x, fill(SVector(1.0), 5, 2), [0.0, 1.0], params)
end
keep(data) = true

@testset "probe_fixes" begin
@testset "finding 9: big-number bound bypasses" begin
    for s in ("(BigInt(3)//1)^(10^7)", "(BigInt(3) + 0im)^(10^6)", "(BigInt(10)^10000)^10000")
        t = @elapsed v = str2val(s)
        println(rpad(s, 30), " -> ", typeof(v), "  ", round(t; digits = 2), " s",
                v isa Number ? "  bits ≈ $(round(Int, log2(abs(float(v isa Rational ? numerator(v) : v isa Complex ? real(v) : v)))))" : "")
        ok = v isa String; v = nothing; @test ok
    end
end

@testset "finding 7: keeping nothing inside containers would not change hashes" begin
    @test val2str((1, nothing)) == val2str((1, Nothing))
    @test val2str([nothing]) == val2str(get_clean_params(Dict(:a => [nothing]))[:a])
end

@testset "finding 3: post-processing still rewrites every file on a cached rerun and drops conversion caches" begin
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :const_solver, :n => 2); postprocess = :keep)
    p = only(generate_tasks(cfg))
    run_all_simulations(cfg; calculate_stats = true)
    enable_cache!(true)
    load_sim_data(p, :eulerian, (9, 2))
    enable_cache!(false)
    @test "conv_E_9x2" in list_available_conversions(p)
    stamp = mtime(get_file_name(p)); sleep(0.05)
    run_all_simulations(cfg; calculate_stats = true)
    @test mtime(get_file_name(p)) == stamp
    @test "conv_E_9x2" in list_available_conversions(p)
end
end
