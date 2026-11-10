# sim_data_table: parameters `file` and `param_file` both present; format_version user entries
include(joinpath(@__DIR__, "common.jl"))
q(f) = with_logger(NullLogger()) do; f(); end
p = create_param_dict(:sim_func_name => :lin_solver, :n => 4, :file => "mesh.msh", :param_file => "other.cfg")
q(() -> save_sim_data(lin_solver(copy(p))))
t = sim_data_table()
println("columns: ", names(t))
println("param_file column = ", repr(t.param_file[1]), "  (parameters: file = \"mesh.msh\", param_file = \"other.cfg\")")
# a 0.4 file whose user entry "format_version" is an Integer >= 2 (it wasn't reserved in 0.4)
r = create_param_dict(:sim_func_name => :lin_solver, :n => 5)
path = q(() -> save_sim_data(lin_solver(copy(r))))
JLD2.jldopen(f -> (for k in ("format_version", "dim_keys", "time_dim"); delete!(f, k); end; f["format_version"] = 7), path, "a+")
println("0.4 file with user format_version = 7: _format_version = ", JLD2.jldopen(PDEStudioCore._format_version, path, "r"),
        "  upgrade_sim_data -> ", only(k for (k, v) in upgrade_sim_data(path) if !isempty(v)),
        "  has dim_keys after: ", JLD2.jldopen(f -> haskey(f, "dim_keys"), path, "r"))
JLD2.jldopen(f -> (delete!(f, "format_version"); f["format_version"] = "user value"), path, "a+")
q(() -> upgrade_sim_data(path))
println("user value \"user value\" after upgrade: ", repr(JLD2.jldopen(f -> f["format_version"], path, "r")))
