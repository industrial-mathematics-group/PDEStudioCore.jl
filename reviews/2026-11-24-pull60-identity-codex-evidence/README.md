# Explicit dictionary keys and stored-file review

`key_boundaries.jl` tests key validation, all ten fixed-width integer endpoints, reversed insertion order and the previous custom-key collision. `store_edges.jl` imports a valid renamed file. `custom_values.jl` uses two declared identities on a custom integer subtype as parameter values and checks what the simulation pipeline returns. The legacy-store check reuses the script from the #58 review.

Run from the root of this review branch. The captured tests used Julia 1.13.4 on Linux and the same resolved package manifest.

```sh
evidence="$PWD/reviews/2026-11-24-pull60-identity-codex-evidence"
legacy="$PWD/reviews/2026-11-24-pull58-identity-codex-evidence/legacy_store.jl"
base=$(mktemp -d)
pre58=$(mktemp -d)
store=$(mktemp -d)
git worktree add --detach "$base" 8952269511c3be1333587f36eda9805303be2135
git worktree add --detach "$pre58" 11537e57546be570a1c207590fe1eb4128b5f82c
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"
cp Manifest.toml "$pre58/Manifest.toml"

julia -t 2 --project "$evidence/key_boundaries.jl"
julia -t 2 --project="$base" "$evidence/key_boundaries.jl"
julia -t 2 --project="$pre58" "$legacy" prepare "$store"
julia -t 2 --project="$base" "$legacy" read "$store"
julia -t 2 --project "$legacy" read "$store"
julia -t 2 --project "$evidence/store_edges.jl"
julia -t 2 --project "$evidence/custom_values.jl"
julia -t 2 --project="$base" "$evidence/custom_values.jl"
julia -t 2 --project="$pre58" "$evidence/custom_values.jl"
```

- [keys-head.txt](keys-head.txt) records stable control hashes and refusal of `TaggedIndex`, `Bool` and `BigInt` keys at `c4800b4f3bafe9ff544fb7d5e60d4412a8e9b4d0).
- [keys-base.txt](keys-base.txt) records the first parent's accepted keys and the earlier wrong cache hit.
- [legacy.txt](legacy.txt) records the prepared store. [legacy-base.txt](legacy-base.txt) and [legacy-head.txt](legacy-head.txt) record the failing and corrected bulk behavior.
- [renamed.txt](renamed.txt) records successfully importing a file under an alternate name.
- [values-head.txt](values-head.txt), [values-base.txt](values-base.txt) and [values-pre58.txt](values-pre58.txt) record the same custom-number value collision on the three revisions.
