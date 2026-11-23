# Reproduction commands

Run from the review checkout with Julia 1.13.4 on Linux. Both snapshots label the package 0.8.0. The reproduction uses disposable files. A supported interactive callback models replacement of an earlier source while the importer waits at the second prompt. The replacement is a complete run written by `save_sim_data` with identical parameters and a different field.

```bash
e="$PWD/reviews/2026-11-23-checked-import-codex-evidence"
t=$(mktemp -d)
git worktree add --detach "$t/previous" 338bcbb294d23faa85fe033e38531e975024d279
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project="$t/previous" -e 'using Pkg; Pkg.instantiate()'
julia -t 2 --project "$e/check.jl"
julia -t 2 --project="$t/previous" "$e/check.jl"
julia -t 2 --project reviews/2026-11-23-v0.8.0-codex-evidence/check.jl
```

[check.jl](check.jl) also replaces an empty destination directory with a regular file to exercise error handling. [Current output](current.txt) and [previous output](previous.txt) record the paired run. [Prior cases](prior-cases.txt) records the preceding review's script on #39.
