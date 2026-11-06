# Shared dataset definitions (public API only, works with old and new code)
using PDEStudioCore, StaticArrays
function make_datasets()
    ds = Pair{String, Any}[]
    x = collect(range(0.0, 1.0; length = 10)); t = collect(range(0.0, 1.0; length = 7))
    push!(ds, "E1D_t" => create_sim_data(x, rand(10, 7), t, create_param_dict(:case => "E1D_t")))
    a = collect(1.0:4.0); b = collect(1.0:5.0); it = collect(0.0:2.0)
    push!(ds, "E2D_iter" => create_sim_data((a, b), rand(4, 5, 3), it, create_param_dict(:case => "E2D_iter");
                                            dims = (:a, :b), time_dim = :iteration))
    push!(ds, "E3D_static_f32" => create_sim_data((Float32.(a), Float32.(b), Float32[0, 1]), rand(Float32, 4, 5, 2),
                                                  create_param_dict(:case => "E3D_static_f32")))
    push!(ds, "E2D_static" => create_sim_data((a, b), rand(4, 5), create_param_dict(:case => "E2D_static")))
    push!(ds, "E1D_t1" => create_sim_data(x, rand(10, 1), [0.5], create_param_dict(:case => "E1D_t1")))
    push!(ds, "E4D_t" => create_sim_data((a, b, [0.0, 1.0], [0.0, 1.0]), rand(4, 5, 2, 2, 3), it,
                                         create_param_dict(:case => "E4D_t")))
    tl = [0.0, 0.5, 1.0]
    xl = [[SVector(rand(), rand()) for _ in 1:(4 + n)] for n in 1:3]
    ul = [[SVector(rand()) for _ in 1:(4 + n)] for n in 1:3]
    push!(ds, "L2D_t" => create_sim_data(xl, ul, tl, create_param_dict(:case => "L2D_t")))
    push!(ds, "L1D_static_f32" => create_sim_data([SVector(Float32(i)) for i in 1:6], Float32.(1:6),
                                                  create_param_dict(:case => "L1D_static_f32")))
    push!(ds, "L1D_t1_iter" => create_sim_data([[SVector(Float64(i)) for i in 1:4]], [[SVector(1.0, 2.0) for _ in 1:4]],
                                               [0.0], create_param_dict(:case => "L1D_t1_iter"); time_dim = :iter))
    push!(ds, "L1D_empty_steps" => create_sim_data([SVector{1, Float64}[], [SVector(1.0)]], [SVector{1, Float64}[], [SVector(1.0)]],
                                                   [0.0, 1.0], create_param_dict(:case => "L1D_empty_steps")))
    return ds
end
