# Reproducing the whole-codebase review

Run from the repository root using Julia 1.13.4 or a compatible Julia version. The captured output used Julia 1.13.4 on Linux. The numerical logs omit the progress bars. The legacy statistics log omits temporary directory paths.

| Evidence | What it shows |
|---|---|
| `pipeline.jl` and `pipeline.txt` | A mixed Float32/Float64 sweep loses a task, reversing source inclusion is treated as a cache hit, and a finite statistic calculated before a reference is configured is not refreshed. Each has a control. |
| `normalization.jl` and `normalization.txt` | An equal set reconstructed with the reverse insertion order creates a second run. Fixed-width unsigned and wider signed integers and BigInt can normalize to Int64. A UInt64 run returns the Int64 run's cache, while its forced computation returns 20. |
| `pipeline-baseline.txt` and `normalization-baseline.txt` | The same cases on the previous full-review snapshot, `c45656de51caf99d21baeeae430245b775063dbd`. |
| `stat_rewrite.jl` and `stat-rewrite.txt` | Saving a metadata edit removes the list of evaluated statistic names. An L1 error calculated with reference A survives an evaluation using B and is served as current. The unedited control returns 6 under B. |
| `numerics.jl`, `numerics-t1.txt` and `numerics-t4.txt` | Linear spatial and nearest-time interpolation agree with an independent expression on an affine field with nonuniform time steps. Three reduced heat examples produce identical final L2 errors under one and four threads. |
| `custom-values.txt` | The earlier #60 custom-integer-value script still reproduces the wrong cache hit. |
| `key-boundaries.txt`, `legacy-store.txt` and `renamed.txt` | Earlier #60 probes still confirm the fixed key boundaries and selective handling of an incompatible legacy file. A renamed source imports. The integer exclusions and renamed-file result support the two guide findings. |
| `legacy-stats.txt` | A mixed-reference cache produced before #50 remains stale after upgrade. A forced statistics pass repairs it. |

```sh
evidence="$PWD/reviews/2026-11-25-full-codebase-codex-evidence"
prior_keys="$PWD/reviews/2026-11-24-pull60-identity-codex-evidence"
legacy_store_script="$PWD/reviews/2026-11-24-pull58-identity-codex-evidence/legacy_store.jl"
legacy_stats_script="$PWD/reviews/2026-11-24-main-c45656d-codex-evidence/legacy_cache.jl"
julia --project -e 'using Pkg; Pkg.instantiate()'
julia -t 2 --project "$evidence/pipeline.jl"
julia -t 2 --project "$evidence/normalization.jl"
julia -t 2 --project "$evidence/stat_rewrite.jl"
julia -t 1 --project "$evidence/numerics.jl"
julia -t 4 --project "$evidence/numerics.jl"
julia -t 2 --project "$prior_keys/custom_values.jl"
julia -t 2 --project "$prior_keys/key_boundaries.jl"
julia -t 2 --project "$prior_keys/store_edges.jl"

baseline=$(mktemp -d)
pre58=$(mktemp -d)
pre50=$(mktemp -d)
legacy_store_root=$(mktemp -d)
legacy_stats_root=$(mktemp -d)
git worktree add --detach "$baseline" c45656de51caf99d21baeeae430245b775063dbd
git worktree add --detach "$pre58" 11537e57546be570a1c207590fe1eb4128b5f82c
git worktree add --detach "$pre50" 2a1014abb8c95a31c53d12a992999cd3c7b24a46
cp Manifest.toml "$baseline/Manifest.toml"
cp Manifest.toml "$pre58/Manifest.toml"
cp Manifest.toml "$pre50/Manifest.toml"
julia -t 2 --project="$baseline" "$evidence/pipeline.jl"
julia -t 2 --project="$baseline" "$evidence/normalization.jl"
julia -t 2 --project="$pre58" "$legacy_store_script" prepare "$legacy_store_root"
julia -t 2 --project "$legacy_store_script" read "$legacy_store_root"
julia -t 2 --project="$pre50" "$legacy_stats_script" prepare "$legacy_stats_root"
julia -t 2 --project "$legacy_stats_script" check "$legacy_stats_root"
```
