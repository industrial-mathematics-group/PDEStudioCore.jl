# Parameter identity boundary checks

`boundaries.jl` exercises named tuples in ordinary parameters and inside identity fields, ordering of dictionary keys that contain declared values, a tie between two distinct ordinary keys, and a one-pass filter over two source files. It uses temporary stores.

Run these commands from the root of this review branch. The captured sessions used Julia 1.13.4 on Linux and the same resolved package manifest.

```sh
evidence="$PWD/reviews/2026-11-24-pull56-identity-codex-evidence"
prior="$PWD/reviews/2026-11-24-pull54-identity-codex-evidence/robustness.jl"
base=$(mktemp -d)
pre54=$(mktemp -d)
store=$(mktemp -d)
git worktree add --detach "$base" bd4dc5069e9bb0a802c36f1e08e8baa5ac72f1e0
git worktree add --detach "$pre54" e14b95d34c5d56f9955fd564ef84a269bbf3f0b0
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"
cp Manifest.toml "$pre54/Manifest.toml"

julia -t 2 --project "$evidence/boundaries.jl"
julia -t 2 --project="$base" "$evidence/boundaries.jl"
julia -t 2 --project "$prior"
julia -t 2 --project="$pre54" "$prior" prepare "$store"
julia -t 2 --project "$prior" read "$store"
```

- [head.txt](head.txt) records eight named-tuple refusals, successful use of an ordinary declared identity, two duplicate runs with different keys, and the correctly filtered import on `e7239b665302c4b95373a791a491dba4b1761d62`.
- [base.txt](base.txt) shows cache reuse in both dictionary cases, the earlier named-tuple acceptance, and the earlier multi-file filter failure.
- [prior.txt](prior.txt) records the previous review script on head, including refusal of both nested name cases and the one-file filtering fix.
- [upgrade.txt](upgrade.txt) records preparation before #54 and a cache hit on #56 for the earlier escaped-string input.
