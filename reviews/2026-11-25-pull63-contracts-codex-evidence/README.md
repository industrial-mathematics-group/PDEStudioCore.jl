# Reproducing the contract review

Run from the repository root. The captured outputs used Julia 1.13.4 on Linux. The symlink probe only runs on Unix.

| Script and output | What it shows |
|---|---|
| `parameters.jl`, `parameters.txt`, `parameters-base.txt` | Public pipeline controls for Int64 endpoints, narrow floats, nested numbers, sets and dictionary keys. The mixed float sweep now errors. Two character values with different declarations still share a cache entry on both versions. |
| `sources.jl`, `sources.txt`, `sources-base.txt` | With the same helper and configuration file contents, changing which file is the last and authoritative source can reuse the old simulation. A repeated absolute path is refused on #63. Two paths to the same file still include it twice. |
| `statistics.jl`, `statistics.txt`, `statistics-base.txt` | A saved deletion through `StatsView` prevents recomputation on #63. A metadata-only edit preserves the correct record. A fresh run with a newly added reference refreshes its finite fallback, while an older reference record can still prevent refresh. Explicitly replacing the solution clears the evaluation records on #63. |
| `metadata-fix.txt` | The original whole-codebase metadata-edit repro now obtains the correct L1 value of 6. |
| `renamed.txt`, `legacy-store.txt` | The #60 import wording agrees with the renamed-file case, and unsupported legacy data still leaves valid files accessible. |

```sh
evidence="$PWD/reviews/2026-11-25-pull63-contracts-codex-evidence"
base=$(mktemp -d)
old=$(mktemp -d)
store=$(mktemp -d)
legacy="$PWD/reviews/2026-11-24-pull58-identity-codex-evidence/legacy_store.jl"
git worktree add --detach "$base" a966a42e953b16665a06fa898f18ad6ae32c303b
git worktree add --detach "$old" 11537e57546be570a1c207590fe1eb4128b5f82c
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"
cp Manifest.toml "$old/Manifest.toml"

for script in parameters sources statistics; do
    julia -t 2 --project "$evidence/$script.jl"
    julia -t 2 --project="$base" "$evidence/$script.jl"
done

julia -t 2 --project reviews/2026-11-25-full-codebase-codex-evidence/stat_rewrite.jl
julia -t 2 --project reviews/2026-11-24-pull60-identity-codex-evidence/store_edges.jl
julia -t 2 --project="$old" "$legacy" prepare "$store"
julia -t 2 --project "$legacy" read "$store"
```
