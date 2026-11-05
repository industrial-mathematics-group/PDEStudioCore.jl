using Test, PDEStudioCore, StaticArrays
set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())
@testset "add_stat! + calculate_all_stats!(save = true)" begin
    x = collect(range(0.0, 1.0, length = 5))
    d = create_sim_data(x, fill(SVector(1.0), 5, 2), [0.0, 1.0], create_param_dict(:case => "addstat"))
    calculate_all_stats!(d)                       # computes and saves
    add_stat!(d, :runtime, 1.5, Symbol[])
    calculate_all_stats!(d)                       # docstring: "With save = true the dataset is saved"
    @test haskey(load_sim_data(create_param_dict(:case => "addstat")).stats, :runtime)
end
