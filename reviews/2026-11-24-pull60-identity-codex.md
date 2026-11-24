# Review of explicit dictionary key types and stored-file validation

| | |
|---|---|
| Reviewed | 2026-11-24. `industrial-mathematics-group/PDEStudioCore.jl` #60 at `c4800b4f3bafe9ff544fb7d5e60d4412a8e9b4d0`, first parent `8952269511c3be1333587f36eda9805303be2135`. Rechecked #58 at `50b1f71cc6c2162b5affd9198569b9e5e08cdee7`, whose first parent is `11537e57546be570a1c207590fe1eb4128b5f82c`. |
| Reviewer | GPT Sol (OpenAI), new session without the generating conversation. |
| Level | A3. Both merges name Claude Opus, a different tier-2 model. New evidence covers key-type boundaries, the public simulation pipeline, and an independently rerun legacy-store check. |
| Highest finding in #60 | `minor` |

Both #58 findings are resolved at their original inputs. The fixed-width integer key controls preserve both endpoints and remain stable under reversed insertion order. The data guide needs two clarifications. A separate custom-number value collision persists from before #58.

## Findings in #60

1. **Minor. The data guide overstates which files import skips.** `docs/src/data.md:168` lists foreign files, including alternate filenames and mismatched filename hashes, then says imports skip those files. A valid run copied to `renamed-run.jld2` outside the store imports successfully under its canonical name. That behavior is useful and remains the documented purpose of import. Clarify that listing and deletion require canonical store filenames, while import validates the contents of an external file and accepts arbitrary source filenames. [Data guide](../docs/src/data.md#L166) · [Import probe](2026-11-24-pull60-identity-codex-evidence/renamed.txt)
2. **Minor. The documented integer key-type family is broader than the allowlist.** `docs/src/data.md:180` and the error at `src/Serialization.jl:554–556` refer to Base integer types. Both `Bool` and `BigInt` are Base integer types that the new rule intentionally excludes. Both worked as dictionary keys on the first parent and raised `ArgumentError` on #60. State that the supported keys are `Symbol`, `String` and the fixed-width signed and unsigned integer types from 8 to 128 bits. [Data guide](../docs/src/data.md#L176) · [Allowlist](../src/Serialization.jl#L520) · [Head and first-parent output](2026-11-24-pull60-identity-codex-evidence/README.md)

## Outside #60

**Critical. Custom integer values can alias runs even when they have explicit declared identities.** The unchanged `Number` branch at `src/Serialization.jl:58–59` renders number subtypes using `string`. The plain-value fast path at `:521` and `:546` skips a custom subtype's identity. I used two `CodingChoice <: Integer` values as ordinary parameter values. Their declared identities differ by `variant`, and their display text is the same number. Both normalized to the integer `2`. The first run returned 10, and the second returned that cached value where its solver would return 20. The same script reproduces on #60, its first parent and before #58. Honor explicit declarations for custom numeric types or define and validate which scalar number types can use the plain-value path. [Rendering](../src/Serialization.jl#L50) · [Validation](../src/Serialization.jl#L520) · [Three-revision output](2026-11-24-pull60-identity-codex-evidence/README.md)

## Earlier findings rechecked

- Both custom-integer key maps from #58 are rejected with the parameter path. On the first parent, the second map reported a cache hit and returned the wrong result.
- A store prepared before #58 with a valid run and a float-key run now lists the valid run, keeps it available by direct lookup and finds it for table generation and dry-run deletion. Tidy lists the float-key file as foreign. Filtered directory import skips it and imports the unrelated valid run. The same store aborts those bulk operations at the first parent.
- Each of the ten fixed-width integer key types preserves its minimum and maximum keys through normalization and hashes identically when inserted in reverse order. The tested `Symbol` and escaped `String` maps also retain their hashes. The re-attestation clears the earlier #58 findings. [Earlier review](2026-11-24-pull58-identity-codex.md) · [Evidence and commands](2026-11-24-pull60-identity-codex-evidence/README.md)

## Commands and results

I read the full #60 diff and traced key handling and stored-parameter validation through hashing, lookup, listing, tidy and import. Local runtime checks used Julia 1.13.4 on Linux. Downstream packages and other operating systems were outside these checks.

| Command | Result |
|---|---|
| `git diff HEAD^ HEAD --check` | No whitespace errors. |
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review` and `uvx --from aisignoff==0.20.1 aisignoff lint` | History enabled. All 82 files and 10,327 lines declared. Five older merges use fallback declarations. |
| `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | All 1,660 tests passed. |
| `julia -t 2 --project key_boundaries.jl` | Ran on head and the first parent. Tested all allowed fixed-width key types and confirmed the original custom-key fix. |
| `julia -t 2 --project legacy_store.jl prepare ROOT` and `julia -t 2 --project legacy_store.jl read ROOT` | Reused the prior review script. Prepared the store before #58, then checked it on the first parent and on #60. |
| `julia -t 2 --project store_edges.jl` | Imported a valid alternate filename and found the result under its canonical key. |
| `julia -t 2 --project custom_values.jl` | Ran on all three revisions, with the same custom-value cache collision on each. |
| `uvx --from aisignoff==0.20.1 aisignoff report --html docs/src/assets/aisignoff.html --with-source`, `julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, and `julia --project=docs docs/make.jl` | Generated the signoff page and built the docs. |

CHANGES SUGGESTED
