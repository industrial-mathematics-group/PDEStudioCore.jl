# Robustness re-review of declared parameter identities

| | |
|---|---|
| Reviewed | 2026-11-24. `industrial-mathematics-group/PDEStudioCore.jl` #54 at `de2b6fa9297e75ad95f930dbaeadd7019bda7061`, first parent `e14b95d34c5d56f9955fd564ef84a269bbf3f0b0`. Re-reviewed #52 at `78a30a82980c0cfac7664066b26a1491e0c09f32`, whose first parent was `c60f98dd2941d58dca312ac37a9d0984cb5cec55`. |
| Reviewer | GPT Sol (OpenAI), new session without the generating conversation. |
| Level | A3 for both merges. Claude Opus and GPT Sol are different tier-2 models, and the new script tests the public pipeline at both revisions and across a cache upgrade. |
| Highest finding in #54 | `major` |

The four original reproductions behave as intended at their original inputs. The same field-name collision still occurs when the named tuple is nested inside a declared identity. The new dictionary ordering also changes some existing format-4 cache keys.

## Findings in #54

1. **Major. Identical declared inputs can miss an existing format-4 cache after upgrade.** `src/Serialization.jl:71–76` sorts dictionary keys by rendered text. For the keys `"phase\tA"` and `"phase0"`, the raw tab sorts before `0`, but the backslash in the rendered tab escape sorts after `0`. I stored a run on the first parent with an ordinary declared `LabelMap` whose field contains that `Dict{String, Int}`. The same solver and parameters on #54 reported that no file existed, ran the solver again, and left two files. The standalone dictionary control kept its old hash because it round-tripped to a dictionary and used the canonical encoder. The declared struct instead retains the rendered dictionary as part of its identity text. Preserve the prior byte order for these supported keys, or change the hash format and document how to find the old runs. Add a cache upgrade test with escaped string keys inside a declared identity. [Dictionary serializer](../src/Serialization.jl#L71) · [Cross-version output](2026-11-24-pull54-identity-codex-evidence/upgrade.txt)
2. **Minor. Filter validation can consume a one-pass import filter before matching.** `src/Serialization.jl:633–635` iterates filter pairs to validate them and then iterates again to match. I called `import_sim_data` on a single source file with parameter `:value => "skip"` and a one-pass `Iterators.Stateful([:value => "keep"])` filter. The first parent imported zero files. #54 imported the file because the second pass saw an empty filter. Materialize or normalize filter pairs once at the import entry point before processing the source files. [Filter validation](../src/Serialization.jl#L631) · [Import call](../src/DataManagement.jl#L185) · [Reproduction output](2026-11-24-pull54-identity-codex-evidence/README.md)

## Outside #54

**Critical. The #52 field-name collision remains for nested named tuples.** `src/Serialization.jl:509–516` checks the fields directly returned by `param_identity`. In `:544–545`, traversal of a plain nested `NamedTuple` checks its values and leaves its field names unchecked. The generic renderer at `:77–83` then inserts those names verbatim. I returned either `(; detail = (; left = 1, right = 2))` or `(; detail = NamedTuple{(Symbol("left=1, right"),)}((2,)))` from the same struct's identity method. Both rendered as `NestedNames(detail=NamedTuple(left=1, right=2))`. The second separate pipeline call returned the first run's field, 10 instead of 20. This variant reproduces on the first parent. Extend the identifier restriction to nested named tuples or encode their field names unambiguously. The re-attestation of #52 retains the existing critical finding. [Traversal](../src/Serialization.jl#L525) · [Head](2026-11-24-pull54-identity-codex-evidence/head.txt) · [First parent](2026-11-24-pull54-identity-codex-evidence/base.txt)

## Earlier findings rechecked

- The direct delimiter-containing field is rejected. The hidden stored field affects `@param_struct` hashes.
- Equivalent declared dictionary keys now give one hash even when omitted fields differ. A dictionary with duplicate declared keys is rejected.
- The earlier `config.sources` case runs from a function. An ordinary declared struct still opens the compatible cache written by the first parent.
- The prior dry-run deletion filter using a function now raises an argument error when a stored candidate is present.

[Prior review](2026-11-24-pull52-identity-codex.md) · [Evidence and reproduction commands](2026-11-24-pull54-identity-codex-evidence/README.md)

## Commands and results

The review covered the full #54 diff, the identity and store code it calls, and the affected #52 behaviors. Downstream applications and other operating systems were outside the local runtime checks.

| Command | Result |
|---|---|
| `git diff HEAD^ HEAD --check` | No whitespace errors. |
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review` and `uvx --from aisignoff==0.20.1 aisignoff lint` | History enabled. All 82 files and 10,237 lines declared. Five older merges use fallback declarations. |
| `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | All 1,643 tests passed on Julia 1.13.4 and Linux. |
| `julia -t 2 --project robustness.jl` | Ran on both revisions. Verified direct fixes, the remaining nested collision and single-pass filter behavior. |
| `julia -t 2 --project robustness.jl prepare ROOT` and `julia -t 2 --project robustness.jl read ROOT` | Prepared the cache on the first parent and read it twice on head. See the shared output for both paths. |
| `julia -t 2 --project reviews/2026-11-24-pull52-identity-codex-evidence/compatibility.jl {prepare,read} ROOT` | Reopened the control cache across versions and re-ran the identity declaration loaded through `config.sources`. |
| `uvx --from aisignoff==0.20.1 aisignoff report --html docs/src/assets/aisignoff.html --with-source`, `julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, and `julia --project=docs docs/make.jl` | Generated the signoff page and checked the split API documentation. |

BLOCKING
