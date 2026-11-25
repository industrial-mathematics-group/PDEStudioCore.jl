# Reproducing the 0.10 whole-codebase review

Run from the repository root. Captured outputs use Julia 1.13.4 on Linux. The quick-start outputs omit progress bars.

| Evidence | What it shows |
|---|---|
| `manual_edit.jl`, `manual-edit.txt`, `manual-edit-base.txt` | Removing an upstream statistic and saving now skips the dependent callback. The 0.9 comparison reports `:ran` and updates the output. Replacing an upstream value without removing its key stays stale in both versions. |
| `layers.jl`, `layers.txt` | A callback can change the kept axis or array shape of an upstream statistic. A failing reference factory prevents a simulation-only statistic from running. The output also shows the stale dependent result after an upstream replacement. |
| `legacy_layers.jl`, `legacy-layers.txt` | Two copies of a store created by 0.9 give different classifications and results, depending on whether the preset has been loaded when 0.10 reads and refreshes them. |
| `public_api.jl`, `public-api.txt`, `public-api-base.txt` | The public statistics call now returns a symbol. A missing statistic method without a reference reports `:cached` in 0.10 and `:failed` in 0.9. |
| `rechecks.jl`, `rechecks.txt` | Nested singleton values and NaN type parameters are refused. Re-registering an inactive L1 statistic after switching references gives the correct 6. The L2 control shows infinity for finite weighted data. |
| `prior-links.txt`, `prior-metadata.txt`, `prior-source-role.txt` | Source hardlinks and symlinks are refused. A legacy user string is preserved on upgrade. A v0.9.0 run with no final-file digest still returns the earlier configuration's result until forced. |
| `quickstart-t1.txt`, `quickstart-t8.txt` | Reduced heat runs and affine resampling agree across thread counts. |

```sh
evidence="$PWD/reviews/2026-11-25-v010-codex-evidence"
earlier="$PWD/reviews/2026-11-25-main-497a7ab-codex-evidence"
base=$(mktemp -d)
pre65=$(mktemp -d)
release09=$(mktemp -d)
legacy=$(mktemp -d)
control=$(mktemp -d)
metadata=$(mktemp -d)
role=$(mktemp -d)
git worktree add --detach "$base" 497a7ab87e0c36cb3c54705ca2bb6d7ca00ded3a
git worktree add --detach "$pre65" c07c3240cae947a4bada40feeb6d6d5a004ceff6
git worktree add --detach "$release09" 189b4704690100fa892e38416d60acbcdea27dca
julia --project -e 'using Pkg; Pkg.instantiate()'
for checkout in "$base" "$pre65" "$release09"; do
    cp Manifest.toml "$checkout/Manifest.toml"
done

julia -t 2 --project "$evidence/layers.jl"
julia -t 2 --project "$evidence/manual_edit.jl"
julia -t 2 --project="$base" "$evidence/manual_edit.jl"
julia -t 2 --project "$evidence/public_api.jl"
julia -t 2 --project="$base" "$evidence/public_api.jl"
julia -t 2 --project="$base" "$evidence/legacy_layers.jl" prepare "$legacy"
cp -r "$legacy/." "$control/"
julia -t 2 --project "$evidence/legacy_layers.jl" check "$control"
julia -t 2 --project "$evidence/legacy_layers.jl" check_without_preset "$legacy"
julia -t 2 --project "$evidence/rechecks.jl"
julia -t 2 --project "$earlier/hardlink.jl"
julia -t 2 --project="$pre65" "$earlier/source_metadata.jl" prepare "$metadata"
julia -t 2 --project "$earlier/source_metadata.jl" check "$metadata"
julia -t 2 --project="$release09" "$earlier/source_upgrade.jl" prepare "$role"
julia -t 2 --project "$earlier/source_upgrade.jl" check "$role"

julia -t 1 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
julia -t 8 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
```
