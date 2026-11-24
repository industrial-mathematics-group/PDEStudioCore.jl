# Reproducing the re-review

`edge_cases.jl` exercises the public simulation and statistics pipeline, parameter hashing and particle scatter. It runs in both checkouts and creates disposable stores. It checks two equal-looking type tags, unregistering and re-registering a reference-dependent statistic, a dry run of the refresh, a mathematical module identifier, and a large Float64 particle state.

`legacy_cache.jl` prepares a mixed-reference cache using the first parent and loads it from the reviewed head. It then demonstrates the recovery using `force_stats = true`.

Run from the root of the review branch, with the first parent checked out in a separate worktree. The captured runs used Julia 1.13.4 on Linux and a shared dependency manifest.

```sh
evidence="$PWD/reviews/2026-11-24-main-c45656d-codex-evidence"
base=$(mktemp -d)
legacy_root=$(mktemp -d)
git worktree add --detach "$base" 2a1014abb8c95a31c53d12a992999cd3c7b24a46
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"

julia -t 2 --project "$evidence/edge_cases.jl"
julia -t 2 --project="$base" "$evidence/edge_cases.jl"
julia -t 2 --project="$base" "$evidence/legacy_cache.jl" prepare "$legacy_root"
julia -t 2 --project "$evidence/legacy_cache.jl" check "$legacy_root"
julia -t 2 --project reviews/2026-11-24-main-8b86a74-codex-evidence/check.jl
```

- [head.txt](head.txt) records the type collision, incorrectly cached L1, dry-run warning, unstable mathematical identifier hash, and Float64 overflow on `c45656de51caf99d21baeeae430245b775063dbd`.
- [base.txt](base.txt) shows the two distinct runs and an outdated statistic on the first parent. The mathematical identifier and Float64 results also reproduce there.
- [legacy.txt](legacy.txt) shows the existing wrong L2 value surviving the upgrade and the subsequent forced refresh giving √2.
- [prior-cases.txt](prior-cases.txt) shows the original fresh-store reference, Unicode and Float32 cases passing on the reviewed head.
