Run on Linux with Julia 1.13.4 and GNU touch. From the review checkout, with both Julia project environments instantiated, run the following. All filesystem experiments use disposable directories.

```bash
e="$PWD/reviews/2026-11-23-v0.7.1-codex-evidence"
t=$(mktemp -d)
git worktree add --detach "$t/v070" 1f1890fd25f5482bf42b6b7176762062cd25aeaa
julia --project="$t/v070" -e 'using Pkg; Pkg.instantiate()'
julia -t 2 --project "$e/check.jl"
julia -t 2 --project="$t/v070" "$e/check.jl"
julia -t 2 --project reviews/2026-11-23-hash-format-3-codex-evidence/check.jl
julia -t 2 --project reviews/2026-11-23-hash-format-3-codex-evidence/native-mass.jl
```

[check.jl](check.jl) exercises cleanup and rehashing. [Current](current.txt) and [previous](previous.txt) capture the first two script runs. [Prior cases](prior-cases.txt) captures the last two.
