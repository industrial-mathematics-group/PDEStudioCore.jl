# Reproduce the 0.9.0 review

Run from a checkout containing these scripts with Julia 1.12 or later. The checked outputs used Linux and Julia 1.13.4. The scripts create temporary stores. Both scripts run at head and at the first parent of #46 with the same dependency manifest.

```sh
evidence=reviews/2026-11-24-v090-codex-evidence
base=$(mktemp -d)
git worktree add --detach "$base" 0a84f60bfe968dbe7806a7086e140c2c662d3d54
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"
julia -t 2 --project "$evidence/check.jl"
julia -t 2 --project="$base" "$evidence/check.jl"
julia -t 2 --project "$evidence/regressions.jl"
julia -t 2 --project="$base" "$evidence/regressions.jl"
```

- [check.jl](check.jl) compares the run identities of two type-valued parameters, the stored mass with an independent sum after post-processing, the statistics status before and after expanding the registry, and a diagnostic explicitly written by the post-processor. [Head output](head.txt) · [First-parent output](base.txt)
- [regressions.jl](regressions.jl) checks imports that remove unused keys, callback parameter isolation, attributes on user JLD2 entries and the refusal to replace an incomplete destination. [Head output](regressions.txt) · [First-parent output](regressions-base.txt)
