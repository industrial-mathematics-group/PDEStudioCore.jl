# Reproduce the review of #42

Run from a checkout containing this report and its evidence. Use Julia with the package project. The scripts make small disposable stores. The base and head declare package version 0.8.0.

```sh
evidence=reviews/2026-11-24-pull42-codex-evidence
base=$(mktemp -d)
git worktree add --detach "$base" 9f4a90d152bd9411c472f8766dcf765882352a78
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"
for test in check exact; do
    julia -t 2 --project "$evidence/$test.jl"
    julia -t 2 --project="$base" "$evidence/$test.jl"
done
store_dir=$(mktemp -d)
julia -t 2 --project="$base" "$evidence/stored.jl" seed "$store_dir"
julia -t 2 --project "$evidence/stored.jl" read "$store_dir"
```

- [check.jl](check.jl) exercises imports of post-processed data and solver-attached diagnostics, exact rational reference grids, JLD2 user entries, and a reference callback receiving task parameters.
- [exact.jl](exact.jl) checks cancellation in an integer mass reduction and a rational grid whose nodes are one unit apart at a large offset. It uses public typed constructors.
- [Head output](head.txt) and [base output](base.txt) contain the results of those two scripts in the order shown above.
- [stored.jl](stored.jl) writes the earlier Float16 example with the base code, then runs the current code on the existing file. [Output](stored.txt) gives the values after a normal run, a forced statistics pass, and a solver rerun.
- [Previous cases](previous-cases.txt) contains the output of the two earlier import/precision scripts and the relevant lines from the failing-writer script. Its uncaught exception is the expected corrected outcome. The package regression test also checks the original bytes and reloads the calibration.
