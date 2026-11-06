# Runs the serialization, round-trip and differential test files of the review checkout (for patched.jl)
using Test, PDEStudioCore, StaticArrays, DataFrames
const TD = "/home/agent/.claude/jobs/d2d299f1/tmp/review-psc1f/repo/test"
PDEStudioCore.set_target_module!(@__MODULE__)
include(joinpath(TD, "solvers.jl"))
@testset "serialization subset" begin
    set_stat_preset!("hyperbolic"); set_save_path!(mktempdir())
    include(joinpath(TD, "test_serialization.jl")); include(joinpath(TD, "test_roundtrip.jl"))
    include(joinpath(TD, "test_str2val_differential.jl"))
end
