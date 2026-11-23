# Reproducing the PDEStudioCore.jl 0.6.3 re-review

[check.jl](check.jl) exercises parameter lookup and replacement, legacy metadata, Float16 interpolation, statistics reference tracking, constructors, derived data, the Burgers example and the two documented custom-statistic formulas. Each case creates its own temporary save root. The legacy metadata case modifies a copy of the repository's v0.4 Eulerian fixture.

From the reviewed checkout, set `previous` to a separate checkout of `d1a8840f0fb11042085a61b600dcd61ae68c8dc7`. The reviewed project is `f0d5b9e2a4b6482a3d80170beb74797f0826edf7`. The recorded comparison used Julia 1.13.4 with the same resolved dependency versions in both environments. The package name, UUID, dependencies and compatibility bounds are the same on both revisions.

```sh
script=reviews/2026-11-23-v0.6.3-codex-evidence/check.jl
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project="$previous" -e 'using Pkg; Pkg.instantiate()'
julia -t 2 --project "$script"
julia -t 2 --project="$previous" "$script"

upgrade_store=$(mktemp -d)
julia -t 2 --project="$previous" "$script" seed "$upgrade_store"
julia -t 2 --project "$script" read "$upgrade_store"

control_store=$(mktemp -d)
julia -t 2 --project="$previous" "$script" seed "$control_store"
julia -t 2 --project="$previous" "$script" read "$control_store"
```

Use fresh temporary directories for the seed/read pairs. The read step intentionally overwrites its test run to check whether another run survives. The script prints observations so the same cases can be compared across releases. The output files are the [current results](current.txt), [previous results](previous.txt), [0.6.2 writer with 0.6.3 reader](upgrade.txt) and [0.6.2 writer and reader control](legacy-control.txt).
