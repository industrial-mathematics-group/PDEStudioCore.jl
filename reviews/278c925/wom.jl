using PDEStudioCore, StaticArrays; const JLD2 = PDEStudioCore.JLD2
set_save_path!(mktempdir())
p = create_param_dict(:wom => 1)
t = [0.0, 1.0]
l = create_sim_data([[SVector(0.1i) for i in 1:4] for _ in t], [[SVector(1.0) for _ in 1:4] for _ in t], t, p)
push!(l.x[2], SVector(9.0))   # inconsistent: 5 positions, 4 states at step 2
r = try save_sim_data(l; verbose = false); "saved" catch e; sprint(showerror, e)[1:min(end, 160)] end
println("inconsistent LSimData: ", r)
# cost of _without_metadata on a large Lagrangian dataset (many time steps)
nt = 20000
l2 = create_sim_data([[SVector(0.1i) for i in 1:10] for _ in 1:nt], [[SVector(1.0) for _ in 1:10] for _ in 1:nt], collect(1.0:nt), create_param_dict(:wom => 2))
PDEStudioCore._without_metadata(l2)
println("_without_metadata LSimData nt=$nt: ", @timed(PDEStudioCore._without_metadata(l2))[[:time, :bytes]])
e = create_sim_data((collect(range(0.0, 1.0, length = 400)), collect(range(0.0, 1.0, length = 400))), [SVector(1.0, 2.0) for i in 1:400, j in 1:400, k in 1:5], collect(1.0:5.0), create_param_dict(:wom => 3))
PDEStudioCore._without_metadata(e)
w = PDEStudioCore._without_metadata(e)
println("_without_metadata ESimData: ", @timed(PDEStudioCore._without_metadata(e))[[:time, :bytes]], " shares u: ", w.u === e.u, " shares params: ", w.params === e.params, " shares axes: ", w.axes[1] === e.axes[1])
