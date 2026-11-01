"""
    PDEStudioCore.Examples

Ready-made simulations: each `test_*()` returns a [`SimulationConfig`](@ref) that runs as it is, e.g.
`run_all_simulations(test_heat_1d())` or, in PDEStudio, `set_sim_config!(test_heat_1d())`.

| Example | Equation | Data | Methods | Sweep |
|:--------|:---------|:-----|:--------|:------|
| [`test_advection_1d`](@ref) | linear advection (hyperbolic) | 1D + time | upwind, Lax–Friedrichs, Lax–Wendroff, exact | CFL number |
| [`test_burgers_1d`](@ref) | inviscid Burgers (nonlinear hyperbolic, shock) | 1D + time | Lax–Friedrichs, Godunov, non-conservative upwind | grid size |
| [`test_heat_1d`](@ref) | heat equation (parabolic) | 1D + time | explicit, implicit, Crank–Nicolson, exact | diffusion number |
| [`test_heat_2d`](@ref) | heat equation (parabolic) | 2D + time | explicit, ADI, exact | diffusion number |
| [`test_poisson_2d`](@ref) | Poisson equation (elliptic) | 2D + iterations | Jacobi, Gauss–Seidel, SOR, exact | grid size |
| [`test_particles_2d`](@ref) | particles in a rotating flow (ODE) | Lagrangian 2D | explicit Euler, RK2, RK4 | time step |

The solvers are ordinary functions of the run's parameters (`solve_*`, `exact_*` for the references), written to be
read: copy one as the starting point of your own. Configurations refer to them by name; names that are not found in
the target module ([`set_target_module!`](@ref)) are looked up here, so a function of your own with the same name
takes precedence.
"""
module Examples

using ..PDEStudioCore
using LinearAlgebra: Tridiagonal, lu, ldiv!
using StaticArrays: SVector

export test_advection_1d, test_burgers_1d, test_heat_1d, test_heat_2d, test_poisson_2d, test_particles_2d

# Time steps of length ≤ `dt_max` that end exactly at `T`
function _time_grid(T, dt_max)
    nt = max(1, ceil(Int, T / dt_max - 1e-9))
    return collect(range(0.0, T, length = nt + 1)), T / nt
end

include("advection_1d.jl")
include("burgers_1d.jl")
include("heat_1d.jl")
include("heat_2d.jl")
include("poisson_2d.jl")
include("particles_2d.jl")

end
