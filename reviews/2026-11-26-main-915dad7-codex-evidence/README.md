# Reproducing the re-review

Captured with Julia 1.13.4 on Linux. Progress and ordinary registry logging are omitted.

| Evidence | Observed result |
|---|---|
| `format_boundary.jl`, `format-prepare.txt`, `format-boundary.txt` | A real 0.9 run is readable. The statistics and post-processing passes, unchanged save and import refuse it. Caching a converted grid changes its bytes. Recompute produces format 4 and retains calibration. |
| `format-edit-head.txt`, `format-edit-base.txt` | Changing the field to `[2, 2]` saves the old `√2` norm under format 4 and blocks refresh. The first parent removes it at save and refreshes to `√8`. |
| `format-misowned.txt`, `format-in-memory.txt` | A file produced by #70 loses its misowned calibration on the direct, in-memory API. The original bytes stay the same. |
| `format-future.txt` | A current-layout test file with a simulated format 5 header is refused on import, but the statistics pass rewrites its header to 4. |
| `l2_rounding.jl`, `l2-head.txt`, `l2-base.txt` | With a normal integration measure the scaled product can round prematurely to zero, losing a representable absolute norm and a relative error of 1. The same script confirms that an undefined component and a partly undefined reference no longer produce zero, and a subnormal partial measure is rejected. |
| `l2_threaded.jl`, `thread8-head.txt` | The maintained-dimension path at eight threads reports an `ArgumentError` for an unsupported measure. |
| `basis-current.txt` | On fresh format 4 data a metadata-only save leaves a completed post-processor cached. |
| `quick-t1.txt`, `quick-t8.txt` | Affine resampling has zero maximum error. The reduced heat example gives identical errors at one and eight threads. |

Run the commands from the reviewed package root. The prior review-only commits used as historical environments have identical package trees to #65 and #70, respectively.

```sh
e="$PWD/reviews/2026-11-26-main-915dad7-codex-evidence"
old=$(mktemp -d)
pr70=$(mktemp -d)
base=$(mktemp -d)
oldstore=$(mktemp -d)
boundary=$(mktemp -d)
edited=$(mktemp -d)
edited_base=$(mktemp -d)
prior_bad=$(mktemp -d)
basis=$(mktemp -d)

git worktree add --detach "$old" 2a9245423e17e7ff21f487fa9b3393a975488afb
git worktree add --detach "$pr70" f7309fc98fe414b552094322c9b3af63db1b5e98
git worktree add --detach "$base" 0864e1229a072096cb03dcecd0286a5f701a2053
julia --project -e 'using Pkg; Pkg.instantiate()'
for checkout in "$old" "$pr70" "$base"; do
    cp Manifest.toml "$checkout/Manifest.toml"
done

julia -t 2 --project="$old" "$e/format_boundary.jl" old "$oldstore"
for destination in "$boundary" "$edited" "$edited_base" "$prior_bad"; do
    cp -r "$oldstore/." "$destination/"
done
julia -t 2 --project "$e/format_boundary.jl" check "$boundary"
julia -t 2 --project "$e/format_boundary.jl" edited "$edited"
julia -t 2 --project="$base" "$e/format_boundary.jl" edited "$edited_base"
julia -t 2 --project="$pr70" "$e/format_boundary.jl" misown "$prior_bad"
julia -t 2 --project "$e/format_boundary.jl" direct "$prior_bad"
julia -t 2 --project "$e/format_boundary.jl" future "$(mktemp -d)"

julia -t 2 --project "$e/l2_rounding.jl"
julia -t 2 --project="$base" "$e/l2_rounding.jl"
timeout 55s julia -t 8 --project "$e/l2_threaded.jl"

julia -t 2 --project reviews/2026-11-26-main-89be634-codex-evidence/basis_upgrade.jl prepare "$basis"
julia -t 1 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
julia -t 8 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
```
