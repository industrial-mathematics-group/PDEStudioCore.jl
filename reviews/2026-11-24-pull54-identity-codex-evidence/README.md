# Identity robustness recheck

`robustness.jl` checks the same declarations at both revisions, and can prepare or reopen a store using a declared struct that contains a dictionary with escaped keys. All stores are temporary. The filter probe imports from one temporary folder into another.

Run from the root of the review branch. The captured runs used Julia 1.13.4 on Linux and the same resolved package manifest.

```sh
evidence="$PWD/reviews/2026-11-24-pull54-identity-codex-evidence"
source_check="$PWD/reviews/2026-11-24-pull52-identity-codex-evidence/compatibility.jl"
base=$(mktemp -d)
store=$(mktemp -d)
control=$(mktemp -d)
git worktree add --detach "$base" e14b95d34c5d56f9955fd564ef84a269bbf3f0b0
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"

julia -t 2 --project "$evidence/robustness.jl"
julia -t 2 --project="$base" "$evidence/robustness.jl"
julia -t 2 --project="$base" "$evidence/robustness.jl" prepare "$store"
julia -t 2 --project "$evidence/robustness.jl" read "$store"
julia -t 2 --project "$evidence/robustness.jl" read "$store"
julia -t 2 --project="$base" "$source_check" prepare "$control"
julia -t 2 --project "$source_check" read "$control"
```

- [head.txt](head.txt) shows the original direct cases fixed, the nested name collision and the imported nonmatching run.
- [base.txt](base.txt) shows the earlier direct and nested collisions and that the one-pass filter excluded the nonmatching source.
- [upgrade.txt](upgrade.txt) shows that the fixed code misses the escaped-key cache from the first parent and then sees the newly created file on a repeat run. The plain dictionary hash stays stable.
- [source.txt](source.txt) shows the compatible control file reopened on head and the source-defined identity accepted.
