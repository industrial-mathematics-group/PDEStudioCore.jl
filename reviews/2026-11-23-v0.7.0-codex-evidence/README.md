# Reproduce the 0.7.0 review

Run these commands in Bash, starting at the root of a checkout containing this review. The three package environments must be instantiated. Use Julia with two threads. The commands create disposable data stores and make all changes to those stores. The default-root case needs a new, empty working directory each time.

```bash
root=$PWD
e="$root/reviews/2026-11-23-v0.7.0-codex-evidence"
t=$(mktemp -d)
git worktree add --detach "$t/v070" fd5cf2bd2c214656eb1cad562ec3c972482fd8a1
git worktree add --detach "$t/v063" f0d5b9e2a4b6482a3d80170beb74797f0826edf7
git worktree add --detach "$t/v062" d1a8840f0fb11042085a61b600dcd61ae68c8dc7
for v in v070 v063 v062; do
    julia --project="$t/$v" -e 'using Pkg; Pkg.instantiate()'
done
for v in v070 v063; do
    mkdir "$t/default-$v"
    (cd "$t/default-$v" && julia -t 2 --project="$t/$v" "$e/check.jl" common)
    julia -t 2 --project="$t/$v" "$e/check.jl" damaged
done
julia -t 2 --project="$t/v063" "$e/check.jl" seed "$t/import"
julia -t 2 --project="$t/v070" "$e/check.jl" inspect "$t/import"
julia -t 2 --project="$t/v062" "$e/check.jl" upgrade04 "$t/control"
julia -t 2 --project="$t/v070" "$e/check.jl" inspect04 "$t/control"
```

- [check.jl](check.jl) creates small native datasets with distinguishable field values. For the overlapping-rename case it sets the same valid timestamp prefix on two 0.6.3 filenames, retaining both original hash suffixes and payloads. For the failed-rehash and missing-raw cases it deliberately damages disposable copies. Package logging is suppressed to keep the observations visible.
- [current.txt](current.txt) and [previous.txt](previous.txt) show the two-save, dictionary-key, singleton/type and Float16 cases on each version.
- [missing-raw.txt](missing-raw.txt) records whether the batch repairs a file missing its solution.
- [upgrade.txt](upgrade.txt) follows actual 0.6.3 writer output through 0.7.0. It also follows a copy of the bundled 0.4 fixture through the upgrade recommended in the documentation.
- [upgrade-control.txt](upgrade-control.txt) uses 0.6.2 for that same fixture upgrade.
