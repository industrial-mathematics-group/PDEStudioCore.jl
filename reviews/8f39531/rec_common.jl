using PDEStudioCore, StaticArrays
using PDEStudioCore.JLD2
mkdata(p) = create_sim_data(collect(0.0:0.1:1.0), [SVector(x + t) for x in 0.0:0.1:1.0, t in (0.0, 0.5)], [0.0, 0.5], p)
const P = create_param_dict(:case => "foreign")
