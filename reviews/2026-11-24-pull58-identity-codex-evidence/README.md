# Dictionary key restriction checks

`key_types.jl` runs the original key shapes, ordinary key-type controls, and two separate simulations whose dictionaries use a user-defined integer type. `legacy_store.jl` creates two runs on the first parent and checks lookup, listing, a table, tidy, dry-run deletion and filtered import with both versions. Reruns use temporary stores and never delete a stored run.

Run from the root of the review branch. The recorded tests used Julia 1.13.4 on Linux and the same resolved package manifest.

```sh
evidence="$PWD/reviews/2026-11-24-pull58-identity-codex-evidence"
base=$(mktemp -d)
store=$(mktemp -d)
git worktree add --detach "$base" 11537e57546be570a1c207590fe1eb4128b5f82c
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"

julia -t 2 --project "$evidence/key_types.jl"
julia -t 2 --project="$base" "$evidence/key_types.jl"
julia -t 2 --project="$base" "$evidence/legacy_store.jl" prepare "$store"
julia -t 2 --project="$base" "$evidence/legacy_store.jl" read "$store"
julia -t 2 --project "$evidence/legacy_store.jl" read "$store"
```

- [keys-head.txt](keys-head.txt) records key-shape validation, stable hashes for the ordinary controls and a second run returning 10 instead of 20 from the cache.
- [keys-base.txt](keys-base.txt) records the same controls and the first parent's refusal of both duplicate-text maps.
- [store-prepare.txt](store-prepare.txt) records the two stored runs and the types of their persisted maps.
- [store-base.txt](store-base.txt) shows that all operations on the shared store succeed on the first parent.
- [store-head.txt](store-head.txt) shows that direct lookup of the ordinary run works on #58 and the bulk operations abort on the previously accepted float-key file.
