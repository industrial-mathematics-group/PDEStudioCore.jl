# Review of the dictionary key restriction in PDEStudioCore.jl

| | |
|---|---|
| Reviewed | 2026-11-24. `industrial-mathematics-group/PDEStudioCore.jl` #58 at `50b1f71cc6c2162b5affd9198569b9e5e08cdee7`, first parent `11537e57546be570a1c207590fe1eb4128b5f82c`. Rechecked #56 at `e7239b665302c4b95373a791a491dba4b1761d62`, whose first parent was `bd4dc5069e9bb0a802c36f1e08e8baa5ac72f1e0`. |
| Reviewer | GPT Sol (OpenAI), new session without the generating conversation. |
| Level | A3 for both merges. Claude Opus and GPT Sol are distinct tier-2 models. New evidence tests the public hashing and simulation APIs on both revisions and opens the same store from each. |
| Highest finding in #58 | `critical` |

The earlier mixed and vector key cases are now rejected. Ordinary supported keys retain their type and produce stable hashes in the cases tested. A custom `Integer` struct can still collapse two distinct maps onto one cache key, and a run written before the restriction can prevent operations on unrelated runs.

## Findings in #58

1. **Critical. A user-defined `Integer` can bypass the plain-key rule and alias distinct runs.** `src/Serialization.jl:537–544` accepts every concrete subtype of `Integer` and removes the previous duplicate-text check. Julia permits user-defined subtypes with distinct keys that render alike. I used `TaggedIndex(1, :left)` and `TaggedIndex(1, :right)` as two distinct keys that each render as `1`. Two dictionaries with the values assigned to opposite keys both normalized to `Dict{TaggedIndex, Int64}(1 => 10, 1 => 20)`. The solver reads the left key. The first configuration returned 10, and the second reported a cache hit and returned 10 when its left value was 20. The first parent rejected both maps with a duplicate-identity error. Restrict the gate to explicitly supported integer key types with canonical encodings, or retain a check for duplicate canonical key text before a run can use the cache. [Key validation](../src/Serialization.jl#L526) · [Rendering](../src/Serialization.jl#L71) · [Head output](2026-11-24-pull58-identity-codex-evidence/keys-head.txt) · [First-parent output](2026-11-24-pull58-identity-codex-evidence/keys-base.txt)
2. **Major. A previously accepted map can abort store scans and directory imports.** The new validation also runs when interpreting parameters saved by earlier revisions. `src/DataManagement.jl:77`, `:195` and `:299` propagate that error from listing, import and tidy. I saved one ordinary run and one run containing a `Dict{Float64,Int64}` on the first parent. On #58, the ordinary run still opens by exact parameters. Its filtered listing, table and dry-run deletion all fail while scanning the other entry. The tidy dry run throws before it can list the unsupported file. An import filtered to the ordinary run aborts at the unsupported source and leaves the ordinary run unimported. All those operations succeed or exclude the nonmatching file at the first parent. Keep the new rule for new inputs and handle validation failures per stored file. Classify such files as foreign where appropriate, and let bulk operations continue with eligible runs. [Listing](../src/DataManagement.jl#L71) · [Import](../src/DataManagement.jl#L188) · [Tidy](../src/DataManagement.jl#L292) · [Store contract](../docs/src/data.md#L109) · [Head output](2026-11-24-pull58-identity-codex-evidence/store-head.txt) · [First-parent output](2026-11-24-pull58-identity-codex-evidence/store-base.txt)

## Outside #58

None observed in the rechecked cases. The first parent rejects the custom two-key maps and handles the shared store without aborting.

## Earlier findings rechecked

The #56 cases with vectors of declared structs as keys and mixed string/symbol keys are rejected before hashing on #58. A direct declared struct key, an abstract `Integer` key type and a `Float64` key type are also rejected. Reversing insertion order gives the same hash in the tested `Symbol`, escaped `String`, `Int8`, `UInt64`, `BigInt` and `Bool` controls. Each control retains its key type after normalization. The user-defined subtype in finding 1 is a distinct case introduced when #58 removed the duplicate-text check. [Earlier review](2026-11-24-pull56-identity-codex.md) · [Test output](2026-11-24-pull58-identity-codex-evidence/keys-head.txt)

## Commands and results

I reviewed the full #58 diff and traced the affected hashing, lookup, listing and import paths. Local runtime checks used Julia 1.13.4 on Linux. Downstream packages and other operating systems were outside these checks.

| Command | Result |
|---|---|
| `git diff HEAD^ HEAD --check` | No whitespace errors. |
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review` and `uvx --from aisignoff==0.20.1 aisignoff lint` | History enabled. All 82 files and 10,272 lines declared. Five older merges use fallback declarations. |
| `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | All 1,652 tests passed. |
| `julia -t 2 --project key_types.jl` | Ran on each revision. Ordinary controls passed. The first parent rejected duplicate text, and #58 returned the wrong cached result. |
| `julia -t 2 --project legacy_store.jl prepare ROOT` and `julia -t 2 --project legacy_store.jl read ROOT` | Prepared the two-file store on the first parent and opened it using both revisions. Only #58 aborted the bulk operations. |
| `uvx --from aisignoff==0.20.1 aisignoff report --html docs/src/assets/aisignoff.html --with-source`, `julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, and `julia --project=docs docs/make.jl` | Generated the signoff page and built the docs. Documenter skipped deployment locally. |

[Evidence and exact worktree commands](2026-11-24-pull58-identity-codex-evidence/README.md)

BLOCKING
