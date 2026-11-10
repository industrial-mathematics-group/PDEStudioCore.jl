using PDEStudioCore, StaticArrays, Logging, Test
const JLD2 = PDEStudioCore.JLD2
set_save_path!(mktempdir())
function lin_solver(params)
    x = collect(range(0.0, 1.0, length = params[:n]))
    return create_sim_data(x, fill(SVector(1.0), length(x), 2), [0.0, 1.0], params)
end
rec(path) = JLD2.jldopen(f -> haskey(f, "postprocessed") ? f["postprocessed"] : nothing, path, "r")
prov(path) = JLD2.jldopen(f -> haskey(f, "provenance") ? f["provenance"] : nothing, path, "r")
