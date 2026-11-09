# _func_name / _func_package / _func_version for closures, anonymous functions, functors, builtins, types
include(joinpath(@__DIR__, "common.jl"))
using PDEStudioCore: _func_name, _func_package, _func_version
struct TypeSolver; data::Any; end
TypeSolver(params::AbstractDict) = lin_solver(params)          # a type used as solver (callable constructor)
struct Fun{T}; x::T; end
(f::Fun)(p) = lin_solver(p)
make_closure(a) = p -> (a; lin_solver(p))
cases = ["named" => lin_solver, "anonymous" => (p -> lin_solver(p)), "closure" => make_closure(1), "functor{T}" => Fun(1.0),
         "builtin tuple" => tuple, "intrinsic" => Core.Intrinsics.add_int, "type (constructor)" => TypeSolver,
         "package fn" => PDEStudioCore.Examples.solve_advection_1d, "Base fn" => sum, "ComposedFunction" => (identity ∘ lin_solver)]
for (k, f) in cases
    println(rpad(k, 20), " name=", repr(_func_name(f)), " package=", _func_package(f), " version=", repr(_func_version(f)))
end
const type_solver = TypeSolver
s = with_logger(NullLogger()) do; run_all_simulations(SimulationConfig(Dict(:sim_func_name => :TypeSolver, :n => 4))); end
println("type as solver: ran=", length(s.ran), " failed=", length(s.failed), " provenance solver=", prov(get_file_name(only(s.tasks)))["solver"])
