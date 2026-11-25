# Reproducing the whole-codebase re-review

Run from the package root. The outputs used Julia 1.13.4 on Linux. Quick-start outputs omit progress bars.

| Evidence | What it shows |
|---|---|
| `ownership.jl`, `ownership-prepare.txt`, `ownership-head.txt`, `ownership-base.txt` | A legacy solver's calibration is claimed by a post-processor after it writes a same-named statistic to a separate scratch dataset. A later statistics refresh deletes the old calibration on #70. The first parent preserves it. |
| `ownership.jl assign`, `assign-head.txt`, `assign-base.txt` | Replacing the whole statistics dictionary inside a callback loses another post-processor's output and misclassifies the newly added statistic on both revisions. |
| `stat_kind_change.jl`, `stat-kind-head.txt`, `stat-kind-base.txt` | A callback can turn a one-component scalar statistic into a one-element series while still passing the upstream fingerprint guard. |
| `legacy_upgrade.jl`, `legacy-upgrade.txt`, `legacy-upgrade-control.txt` | An intermediate save with the first 0.10 implementation persists an incorrect legacy layer record. On #70 a reference refresh then drops mass. Opening the original 0.9 file directly preserves mass. |
| `fallback_name.jl`, `fallback-name.txt`, `fallback-name-base.txt` | A legitimate implementation with the classifier's probe name is incorrectly rejected and hides subsequently missing implementations. |
| `l2.jl`, `l2-head.txt`, `l2-base.txt` | The earlier single-axis weighted overflow is fixed. Overflow or underflow in the integration measure and nonzero subnormal intermediate terms still give inaccurate norms compared with the BigFloat calculation. |
| `prior-layers.txt`, `prior-manual_edit.txt`, `prior-public_api.txt`, `prior-legacy-layers.txt`, `prior-rechecks.txt` | Original 0.10 review cases re-run. The manual edit, direct axis and shape changes, unused factory, ordinary missing statistic method, return value, direct 0.9 migration, hash inputs, inactive L1 and original L2 control behave as expected. |
| `quick-t1.txt`, `quick-t8.txt` | Reduced heat and affine resampling controls with one and eight Julia threads. |

```sh
evidence="$PWD/reviews/2026-11-25-main-a4089e3-codex-evidence"
prior="$PWD/reviews/2026-11-25-v010-codex-evidence"
base=$(mktemp -d)
old=$(mktemp -d)
store=$(mktemp -d)
store_base=$(mktemp -d)
upgrade=$(mktemp -d)
upgrade_control=$(mktemp -d)
legacy_check=$(mktemp -d)
legacy_check_control=$(mktemp -d)
git worktree add --detach "$base" 2ae62f7cd0b1942e6fe4298896adb73ff5ca59dc
git worktree add --detach "$old" 497a7ab87e0c36cb3c54705ca2bb6d7ca00ded3a
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"
cp Manifest.toml "$old/Manifest.toml"

julia -t 2 --project="$old" "$evidence/ownership.jl" prepare "$store"
cp -r "$store/." "$store_base/"
julia -t 2 --project "$evidence/ownership.jl" check "$store"
julia -t 2 --project="$base" "$evidence/ownership.jl" check "$store_base"
julia -t 2 --project "$evidence/ownership.jl" assign
julia -t 2 --project="$base" "$evidence/ownership.jl" assign
for script in l2 fallback_name stat_kind_change; do
    julia -t 2 --project "$evidence/$script.jl"
    julia -t 2 --project="$base" "$evidence/$script.jl"
done

julia -t 2 --project="$old" "$prior/legacy_layers.jl" prepare "$upgrade"
cp -r "$upgrade/." "$upgrade_control/"
julia -t 2 --project="$base" "$evidence/legacy_upgrade.jl" resave "$upgrade"
julia -t 2 --project "$evidence/legacy_upgrade.jl" refresh "$upgrade"
julia -t 2 --project "$evidence/legacy_upgrade.jl" refresh "$upgrade_control"

for script in layers manual_edit public_api rechecks; do
    julia -t 2 --project "$prior/$script.jl"
done
julia -t 2 --project="$old" "$prior/legacy_layers.jl" prepare "$legacy_check"
cp -r "$legacy_check/." "$legacy_check_control/"
julia -t 2 --project "$prior/legacy_layers.jl" check "$legacy_check_control"
julia -t 2 --project "$prior/legacy_layers.jl" check_without_preset "$legacy_check"
julia -t 1 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
julia -t 8 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
```
