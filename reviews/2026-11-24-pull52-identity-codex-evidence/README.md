# Declared parameter identity evidence

`identities.jl` makes temporary stores and checks an explicit identity, validation errors, two separate simulation runs, automatic field selection, dictionary ordering, and a dry-run filter. `compatibility.jl` saves a simple struct on the first parent, checks it on head with an explicit all-fields declaration, and exercises a source-defined identity.

Run from the root of this review branch on Julia 1.13.4. Use a separate worktree for the first parent and share the resolved manifest.

```sh
evidence="$PWD/reviews/2026-11-24-pull52-identity-codex-evidence"
base=$(mktemp -d)
store=$(mktemp -d)
git worktree add --detach "$base" c60f98dd2941d58dca312ac37a9d0984cb5cec55
julia --project -e 'using Pkg; Pkg.instantiate()'
cp Manifest.toml "$base/Manifest.toml"

julia -t 2 --project "$evidence/identities.jl"
julia -t 2 --project="$base" "$evidence/identities.jl"
julia -t 2 --project "$evidence/identities.jl" visible
julia -t 2 --project="$base" "$evidence/compatibility.jl" prepare "$store"
julia -t 2 --project "$evidence/compatibility.jl" read "$store"
julia -t 2 --project reviews/2026-11-24-main-c45656d-codex-evidence/edge_cases.jl
```

- [head.txt](head.txt) shows the identity collisions and distinct hashes for equivalent dictionary entries on `78a30a82980c0cfac7664066b26a1491e0c09f32`.
- [base.txt](base.txt) shows that the delimiter example represented two separate runs on the first parent. The old macro-free serialization still ignores a hidden field.
- [visible.txt](visible.txt) is a new process on head that imports the fieldless tag type before hashing. Its output matches `head.txt` byte for byte.
- [compatibility.txt](compatibility.txt) records the shared pre-existing cache filename, the source-defined declaration error and the successful latest-world retry.
- [prior.txt](prior.txt) records the earlier #50 probes on head. The statistics and dry-run cases pass and the remaining type-name and Float64 behavior match the new documented contract.
