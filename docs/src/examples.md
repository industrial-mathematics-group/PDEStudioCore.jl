# Examples

```@docs
PDEStudioCore.Examples
```

Every example runs as it is:

```julia
using PDEStudioCore
set_stat_preset!("hyperbolic")
set_save_path!("results")
run_all_simulations(test_poisson_2d(); parallel = true, calculate_stats = true)
```

or, in PDEStudio, `set_sim_config!(test_poisson_2d())` (for `test_particles_2d`, `set_mode!(:lagrangian)` first).
The solvers are in [`src/Examples/`](https://github.com/blhackslash/PDEStudioCore.jl/tree/main/src/Examples), one
file per example.

## Configurations

```@docs
test_advection_1d
test_burgers_1d
test_heat_1d
test_heat_2d
test_poisson_2d
test_particles_2d
```

## Solvers and exact solutions

```@docs
PDEStudioCore.Examples.solve_advection_1d
PDEStudioCore.Examples.exact_advection_1d
PDEStudioCore.Examples.solve_burgers_1d
PDEStudioCore.Examples.solve_heat_1d
PDEStudioCore.Examples.exact_heat_1d
PDEStudioCore.Examples.solve_heat_2d
PDEStudioCore.Examples.exact_heat_2d
PDEStudioCore.Examples.solve_poisson_2d
PDEStudioCore.Examples.exact_poisson_2d
PDEStudioCore.Examples.solve_particles_2d
PDEStudioCore.Examples.exact_particles_2d
```
