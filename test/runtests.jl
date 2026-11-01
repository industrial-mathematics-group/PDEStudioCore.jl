using Test
using PDEStudioCore
using StaticArrays
using DataFrames

# Register this module so the pipeline can resolve solvers/references/post-processing by name.
PDEStudioCore.set_target_module!(@__MODULE__)

include("solvers.jl")

@testset "PDEStudioCore.jl" begin
    set_stat_preset!("hyperbolic")
    set_save_path!(mktempdir())
    @test NoSimData() isa NoSimData

    include("test_types.jl")
    include("test_constructors.jl")
    include("test_serialization.jl")
    include("test_statistics.jl")
    include("test_pipeline.jl")
    include("test_data.jl")

    include("test_examples.jl")
end
