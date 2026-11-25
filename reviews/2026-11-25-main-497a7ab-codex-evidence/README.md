# Reproducing the whole-codebase review

Run from the repository root. The captured outputs used Julia 1.13.4 on Linux. The numerical outputs omit info logs and progress bars. The old character repro deliberately exits on the expected refusal; only its first error line is included.

| Evidence | What it shows |
|---|---|
| `parameters.jl`, `parameters.txt`, `parameters-base.txt` | Ordinary nested `nothing` and the type `Nothing` share a cache entry. The same hash collision occurs for nested `missing` and `Missing`. Distinct `Val` types carrying different Float64 NaN payloads also share a cache entry. Fresh calculations return different solutions. |
| `statistics.jl`, `statistics.txt`, `statistics-base.txt` | Rotating the active statistic registry can keep an L1 error while losing its evaluation record. Changing from A to B and re-registering L1 returns 2 instead of 6. |
| `source_metadata.jl`, `source-metadata.txt` | On upgrade, a previously stored user string called `:configuration_source` is mistaken for an old digest. It triggers a recomputation with unchanged source bytes and is replaced by the system digest. |
| `source_upgrade.jl`, `source-fresh.txt`, `source-legacy.txt` | The configuration-source role switch triggers recomputation with a new store. A store written by the first parent still returns the prior configuration's result. |
| `hardlink.jl`, `hardlink.txt`, `hardlink-base.txt` | A symlink alias is rejected on #65 before inclusion. Both versions include a source twice via a hardlink. |
| `numerics.jl`, `numerics.txt`, `numerics-base.txt` | The health check reports an infinite mean for a finite constant field. The L2 preset squares before applying the integration measure and reports infinity where a higher-precision calculation is finite. |
| `prior-sources.txt`, `prior-statistics.txt`, `prior-character.txt` | The source-role switch on fresh data, symbolic-link rejection, saved-statistic deletion, restoration of an earlier reference and custom-character refusal all pass the #64 rechecks. |
| `quickstart-t1.txt`, `quickstart-t4.txt` | A reduced example runs on one and four threads with identical final errors. The affine-grid resampling control agrees with the independent expression. |

```sh
evidence="$PWD/reviews/2026-11-25-main-497a7ab-codex-evidence"
prior="$PWD/reviews/2026-11-25-pull63-contracts-codex-evidence"
base=$(mktemp -d)
legacy=$(mktemp -d)
fresh=$(mktemp -d)
metadata=$(mktemp -d)
git worktree add --detach "$base" c07c3240cae947a4bada40feeb6d6d5a004ceff6
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"

for script in parameters statistics numerics hardlink; do
    julia -t 2 --project "$evidence/$script.jl"
    julia -t 2 --project="$base" "$evidence/$script.jl"
done

julia -t 2 --project="$base" "$evidence/source_upgrade.jl" prepare "$legacy"
julia -t 2 --project "$evidence/source_upgrade.jl" check "$legacy"
julia -t 2 --project "$evidence/source_upgrade.jl" prepare "$fresh"
julia -t 2 --project "$evidence/source_upgrade.jl" check "$fresh"
julia -t 2 --project="$base" "$evidence/source_metadata.jl" prepare "$metadata"
julia -t 2 --project="$base" "$evidence/source_metadata.jl" check "$metadata"
julia -t 2 --project "$evidence/source_metadata.jl" check "$metadata"

julia -t 2 --project "$prior/sources.jl"
julia -t 2 --project "$prior/statistics.jl"
julia -t 1 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
julia -t 4 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
julia -t 2 --project "$prior/parameters.jl"  # expected ArgumentError when it reaches CharChoice
```
