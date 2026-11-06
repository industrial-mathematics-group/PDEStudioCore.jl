# Runs test/test_roundtrip.jl with the previous parser in place of str2val (which of its tests fail at the old code).
using PDEStudioCore, StaticArrays, Test
include(joinpath(@__DIR__, "../repo/test/reference_str2val.jl"))
module OldRT
using PDEStudioCore: val2str
using StaticArrays, Test
const str2val = Main.OldStr2Val.str2val
include(joinpath(@__DIR__, "../repo/test/test_roundtrip.jl"))
end
