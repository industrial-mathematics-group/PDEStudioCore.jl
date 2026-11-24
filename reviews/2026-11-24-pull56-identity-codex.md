# Re-review of parameter identity and cache ordering

| | |
|---|---|
| Reviewed | 2026-11-24. `industrial-mathematics-group/PDEStudioCore.jl` #56 at `e7239b665302c4b95373a791a491dba4b1761d62`, first parent `bd4dc5069e9bb0a802c36f1e08e8baa5ac72f1e0`. Re-reviewed #54 at `de2b6fa9297e75ad95f930dbaeadd7019bda7061` (first parent `e14b95d34c5d56f9955fd564ef84a269bbf3f0b0`) and #52 at `78a30a82980c0cfac7664066b26a1491e0c09f32` (first parent `c60f98dd2941d58dca312ac37a9d0984cb5cec55`). |
| Reviewer | GPT Sol (OpenAI), new session without the generating conversation. |
| Level | A3. The reviewed merges name Claude Opus, a different tier-2 model. The evidence includes new public-pipeline tests on both revisions and an independently rerun cache upgrade. |
| Highest finding in #56 | `major` |

The previous named-tuple collision is closed across the tested positions, and the one-pass filter and original escaped-string cache checks pass. The restored dictionary order introduces two cases where equivalent inputs now run twice.

## Findings in #56

1. **Major. An array used as a dictionary key can make ignored struct fields change the run identity.** At `src/Serialization.jl:75` and `:510`, the new choice between rendered text and `string(key)` looks through tuples and pairs. An array containing a declared value falls back to `string(key)`, which includes its omitted fields. I used one-element vectors of `KeyWithWork` as dictionary keys, declared only `id`, and swapped the omitted `work` values of keys 1 and 2. The canonical key/value pairs stayed the same. Their rendered order flipped, and the second configuration ran again and created a second file. At the first parent, the two configurations shared a hash and the second was cached. A tuple containing the vector also reproduced the mismatch. Extend the declared-value check through supported container keys, or derive ordering directly from their canonical representation. Keep a compatibility check for associative values stored as text. [Sort branch](../src/Serialization.jl#L71) · [Declared-value check](../src/Serialization.jl#L510) · [Head](2026-11-24-pull56-identity-codex-evidence/head.txt) · [First parent](2026-11-24-pull56-identity-codex-evidence/base.txt)
2. **Major. Equal dictionaries can hash differently when two distinct keys have identical display text.** At `src/Serialization.jl:75`, both `"label_2"` and `:label_2` sort under the display text `"label_2"`. They are distinct parameter values. I built two equal `Dict{Any,Int}` instances with those keys and identical mappings in reverse insertion order, then used each as a declared struct field. The sort tie preserved the different iteration orders, so the two equal instances stored different identity text. The second configuration ran again and created a second file. The first parent sorted by stored text, produced one hash and reused the cache. Add a deterministic tie-breaker based on canonical key text, and account for stored results whose keys already triggered a tie. [Sort branch](../src/Serialization.jl#L71) · [Head](2026-11-24-pull56-identity-codex-evidence/head.txt) · [First parent](2026-11-24-pull56-identity-codex-evidence/base.txt)
3. **Minor. The data guide describes the previous dictionary order.** `docs/src/data.md:182` says keys are ordered by stored form. The compatibility probe shows ordinary `"phase\tA"` sorting before `"phase0"` even though the escaped stored form sorts after it. This is the intended compatibility behavior of the new sort. Describe the compatibility rule and the ordering of keys that contain declared values. [Data guide](../docs/src/data.md#L176) · [Cache-upgrade output](2026-11-24-pull56-identity-codex-evidence/upgrade.txt)

## Outside #56

None observed in the rechecked cases. Both dictionary regressions reproduce by comparison with the immediate first parent.

## Earlier findings rechecked

- The prior #52 collision is rejected at the nested identity field, and a regular `param_identity` method returning a named tuple still works. The new probe checks rejection at eight positions, including dictionary keys, pairs, sets and vectors. The hidden stored-field and duplicate-key cases retain their earlier fixes. The suite also passes the `config.sources` declaration test.
- A cache written before #54 using the original escaped-string input opens on #56, and the solver stays cached. The original one-file filter excludes its nonmatching source. The new two-file probe imports only the matching file with the same one-pass iterator.
- The #52 and #54 records clear the earlier scoped findings. The new dictionary regressions are recorded on #56.

[Prior review](2026-11-24-pull54-identity-codex.md) · [Earlier-reproduction output](2026-11-24-pull56-identity-codex-evidence/prior.txt) · [Evidence and commands](2026-11-24-pull56-identity-codex-evidence/README.md)

## Commands and results

I reviewed the full #56 diff and followed identity validation and rendering through task generation, cache lookup and import. The local runtime checks used Julia 1.13.4 on Linux. Downstream packages and other platforms were outside the local checks.

| Command | Result |
|---|---|
| `git diff HEAD^ HEAD --check` | No whitespace errors. |
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review` and `uvx --from aisignoff==0.20.1 aisignoff lint` | History enabled. All 82 files and 10,269 lines declared. Five older merges use fallback declarations. |
| `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | All 1,647 tests passed. |
| `julia -t 2 --project boundaries.jl` | Ran on head and first parent. Verified the named-tuple boundary, differing outcomes for the two dictionary cases and multi-file import filtering. |
| `julia -t 2 --project reviews/2026-11-24-pull54-identity-codex-evidence/robustness.jl` | Rechecked the previous identity and filter cases on head. |
| `julia -t 2 --project robustness.jl prepare ROOT` and `julia -t 2 --project robustness.jl read ROOT` | Prepared a cache before #54 and opened it on #56. The exact worktree commands appear in the evidence README. |
| `uvx --from aisignoff==0.20.1 aisignoff report --html docs/src/assets/aisignoff.html --with-source`, `julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, and `julia --project=docs docs/make.jl` | Generated the signoff page and built the docs. |

BLOCKING
