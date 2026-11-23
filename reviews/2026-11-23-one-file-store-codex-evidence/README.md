All writes use disposable simulation directories. Run from the review checkout on Linux with Julia. The two commits use the same package version, so the output identifies them by hash format.

```bash
e="$PWD/reviews/2026-11-23-one-file-store-codex-evidence"
t=$(mktemp -d)
git worktree add --detach "$t/previous" 8fdead725ef6898db6f199668d52af36f6272b72
julia --project="$t/previous" -e 'using Pkg; Pkg.instantiate()'
julia -t 2 --project "$e/check.jl"
julia -t 2 --project="$t/previous" "$e/check.jl"
julia -t 2 --project="$t/previous" "$e/check.jl" seed "$t/store"
julia -t 2 --project "$e/check.jl" import "$t/store"
```

[Current output](current.txt) records the import and save checks. [Previous output](previous.txt) records the existing deletion-filter behavior and the earlier behavior of a solver that returns no dataset. [Legacy import](legacy.txt) verifies that a real 0.7.1 file's bytes remain intact and that its field and metadata are accessible after import. The [script](check.jl) loads JLD2 entries directly only when constructing a deliberately invalid fixture or checking what the public API wrote.
