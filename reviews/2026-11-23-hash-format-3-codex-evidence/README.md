# Reproducing the hash-format-3 review

The scripts use small disposable datasets. `check.jl` exercises two overwrite guards, two batch rehash cases, cleanup, an integer particle dataset, and the lifetime of cached parameters. On Linux it uses `touch -r` to model a replacement that preserves the original modification time, and a valid 252-byte filename to exercise the filesystem component-length limit. Its counters inspect stored payloads and visible files. `native-mass.jl` compares the same constant-density particles in Float16 and Float32.

From the review checkout, run the following in Bash with Julia installed. Both implementation snapshots identify themselves as package version 0.7.0. The commits distinguish them.

```bash
root=$PWD
e="$root/reviews/2026-11-23-hash-format-3-codex-evidence"
old="$root/reviews/2026-11-23-v0.7.0-codex-evidence/check.jl"
t=$(mktemp -d)
git worktree add --detach "$t/current" 1f1890fd25f5482bf42b6b7176762062cd25aeaa
git worktree add --detach "$t/previous" fd5cf2bd2c214656eb1cad562ec3c972482fd8a1
git worktree add --detach "$t/v063" f0d5b9e2a4b6482a3d80170beb74797f0826edf7
for v in current previous v063; do
    julia --project="$t/$v" -e 'using Pkg; Pkg.instantiate()'
done
for v in current previous; do
    julia -t 2 --project="$t/$v" "$e/check.jl"
    julia -t 2 --project="$t/$v" "$e/native-mass.jl"
done
mkdir "$t/default"
(cd "$t/default" && julia -t 2 --project="$t/current" "$old" common)
julia -t 2 --project="$t/current" "$old" damaged
julia -t 2 --project="$t/v063" "$old" seed "$t/store"
julia -t 2 --project="$t/current" -e 'using PDEStudioCore; set_save_path!(ARGS[1]); for k in ["hello",repr("hello")]; @show does_sim_data_exist(create_param_dict(:k=>k)); end; rehash_sim_data(); for k in ["hello",repr("hello")]; @show k first(first(load_sim_data(create_param_dict(:k=>k)).u)); end' "$t/store/overlap"
```

[Current output](current.txt) and [previous output](previous.txt) are from [check.jl](check.jl). [Native mass results](native-mass.txt) are from [native-mass.jl](native-mass.jl). [Prior cases](prior-cases.txt) records the current behavior of the preceding review's reproducer, including the original same-timestamp rehash case.
