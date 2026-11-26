# Reproducing the whole-codebase review

Run from the package root. Captured runs used Julia 1.13.4 on Linux. Quick-start outputs omit progress bars.

| Evidence | What it shows |
|---|---|
| `l2_edges.jl`, `l2-edges-head.txt`, `l2-edges-base.txt` | #72 turns an undefined L2 component into zero when the only defined contributions are zero. It also returns a zero error for a partly undefined reference. Both revisions get the same inaccurate weighted norm when a subnormal intermediate measure later becomes normal. |
| `basis_upgrade.jl`, `basis-prepare.txt`, `basis-head.txt`, `basis-base.txt` | The same metadata-only save leaves a callback cached on the first parent and causes a second invocation on #72. |
| `ownership_upgrade.jl`, `ownership-upgrade.txt`, `ownership-upgrade-control.txt` | A misowned calibration record written by #70 remains present after upgrading, then loses the solver value on refresh. The original 0.9 file opened directly under #72 preserves it. |
| `prior-ownership.txt`, `prior-assign.txt`, `prior-stat_kind_change.txt`, `prior-fallback_name.txt` | The original scratch-write, bulk dictionary assignment, scalar-versus-series and classifier-name cases pass on #72. |
| `prior-legacy-upgrade.txt`, `prior-l2.txt` | A mass statistic mislabeled by the initial, pre-fingerprint 0.10 implementation survives the upgrade and refresh. The previous overflowing, underflowing and subnormal L2 cases agree with the independent calculation. |
| `quick-t1.txt`, `quick-t8.txt` | Reduced heat and affine resampling controls at one and eight threads. |

```sh
evidence="$PWD/reviews/2026-11-26-main-89be634-codex-evidence"
prior="$PWD/reviews/2026-11-25-main-a4089e3-codex-evidence"
old_review="$PWD/reviews/2026-11-25-v010-codex-evidence"
base=$(mktemp -d)
old=$(mktemp -d)
early=$(mktemp -d)
basis=$(mktemp -d)
basis_control=$(mktemp -d)
ownership=$(mktemp -d)
ownership_control=$(mktemp -d)
clean_check=$(mktemp -d)
layer_upgrade=$(mktemp -d)
git worktree add --detach "$base" d2c207e3c883773cdf2544f91fd863374ee56afe
git worktree add --detach "$old" 497a7ab87e0c36cb3c54705ca2bb6d7ca00ded3a
git worktree add --detach "$early" 2ae62f7cd0b1942e6fe4298896adb73ff5ca59dc
julia --project -e 'using Pkg; Pkg.instantiate()'
for checkout in "$base" "$old" "$early"; do cp Manifest.toml "$checkout/Manifest.toml"; done

julia -t 2 --project "$evidence/l2_edges.jl"
julia -t 2 --project="$base" "$evidence/l2_edges.jl"
julia -t 2 --project="$base" "$evidence/basis_upgrade.jl" prepare "$basis"
cp -r "$basis/." "$basis_control/"
julia -t 2 --project="$base" "$evidence/basis_upgrade.jl" check "$basis_control"
julia -t 2 --project "$evidence/basis_upgrade.jl" check "$basis"

julia -t 2 --project="$old" "$prior/ownership.jl" prepare "$ownership"
cp -r "$ownership/." "$ownership_control/"
julia -t 2 --project="$base" "$evidence/ownership_upgrade.jl" save_ownership "$ownership"
julia -t 2 --project "$evidence/ownership_upgrade.jl" refresh "$ownership"
julia -t 2 --project "$evidence/ownership_upgrade.jl" refresh "$ownership_control"

julia -t 2 --project="$old" "$prior/ownership.jl" prepare "$clean_check"
julia -t 2 --project "$prior/ownership.jl" check "$clean_check"
julia -t 2 --project "$prior/ownership.jl" assign
for script in stat_kind_change fallback_name l2; do julia -t 2 --project "$prior/$script.jl"; done
julia -t 2 --project="$old" "$old_review/legacy_layers.jl" prepare "$layer_upgrade"
julia -t 2 --project="$early" "$prior/legacy_upgrade.jl" resave "$layer_upgrade"
julia -t 2 --project "$prior/legacy_upgrade.jl" refresh "$layer_upgrade"

julia -t 1 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
julia -t 8 --project reviews/2026-11-25-full-codebase-codex-evidence/numerics.jl
```
