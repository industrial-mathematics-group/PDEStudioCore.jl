# Review of the parameter, source and statistics contracts

| | |
|---|---|
| Reviewed | 2026-11-25. `industrial-mathematics-group/PDEStudioCore.jl` #63 at `5222e2c2d80770ecbf7e2f8a5c32b86587350d41`, first parent `a966a42e953b16665a06fa898f18ad6ae32c303b`. Rechecked the #60 documentation findings at `c4800b4f3bafe9ff544fb7d5e60d4412a8e9b4d0`, first parent `8952269511c3be1333587f36eda9805303be2135`, and the prior whole-codebase findings in #62. |
| Reviewer | GPT Sol (OpenAI), new session without the generating conversation. |
| Level | A3 for #63 and the #60 recheck. Both changes declare Claude Opus, a different tier-2 model, and the review includes new runnable evidence. The overlapping whole-file attestations for the data guide, serialization and storage remain A1 because their older lines include Claude Fable. The whole simulation pipeline qualifies for A3. |
| Highest finding in #63 | `major` |

The original number and set cases are now refused, and the mixed-precision sweep reports a collision. The metadata-only save and first-time reference cases now produce correct statistics. Persistently removing one computed statistic via the documented dictionary API exposes a separate cache regression.

## Findings in #63

1. **Major. A saved statistic deletion can suppress recomputation on later runs.** `src/IOUtils.jl:421–425` preserves every previously evaluated name when the numeric solution is unchanged. Calculate a registered statistic, call `delete!(data.stats, :aux)`, save with `overwrite = true`, and run the same configuration with `calculate_stats = true`. The pipeline returns `:cached` while `:aux` is absent because `_needs_stats` treats the retained name as an evaluation with no stored result. The first parent recalculated `:aux`. Metadata-only saves should preserve the record. For statistics removed by an edit, drop their evaluation entries so the next pass recomputes them. A forced statistics pass repairs the affected case, and deleting the registry entry via `delete_stat!(data, :aux)` also lets the subsequent pass recompute it. [Save path](../src/IOUtils.jl#L416) · [Cache test](../src/Simulations.jl#L533) · [Current output](2026-11-25-pull63-contracts-codex-evidence/statistics.txt) · [First parent](2026-11-25-pull63-contracts-codex-evidence/statistics-base.txt)
2. **Minor. Duplicate-source detection misses two paths to the same file.** `src/Simulations.jl:367–370` checks normalized absolute paths. An exact repeat is rejected before any include. A source and a symbolic link to it passed the check and executed the same file twice, as a counter in the source verified. Compare the file identity or canonical path before inclusion, or document the check as rejecting repeated paths and require callers to avoid aliases. [Duplicate check](../src/Simulations.jl#L367) · [Execution counts](2026-11-25-pull63-contracts-codex-evidence/sources.txt)

## Outside #63

1. **Critical. A custom character can still bypass its declared parameter identity.** The `AbstractChar` branch at `src/Serialization.jl:56` and the plain-value shortcut at `:525` and `:550` admit a custom character without using its declaration. Two `CharChoice` values declare distinct variants and share display text `'a'`. The right variant returned the left run's cached value of 10, and forcing it returned 20. Both revisions reproduce the collision. The character path predates #63 and is separate from the corrected number whitelist. Restrict plain characters to the built-in type or encode an explicit custom character identity. [Rendering](../src/Serialization.jl#L54) · [Two-revision evidence](2026-11-25-pull63-contracts-codex-evidence/README.md)
2. **Major. The earlier source-order issue persists when the configuration file changes roles.** `src/Simulations.jl:354` still compares the set of digests. I made two configurations, each with one helper and its own file last. Each final file overrides the solver from its helper, as the new contract permits. Both configurations list the same two files and share run parameters. With `b.jl` last the solution was 20. Switching to the other configuration with `a.jl` last and `on_changed_sources = :recompute` returned cached 20 and zero changed tasks. Forcing it returned 10. Both revisions reproduce this. The reordered-dependent-helpers example is outside the new contract, while moving a file into the explicitly order-sensitive configuration role still needs source provenance. Record a distinguished digest for the configuration file alongside the unordered helper digests. [Source contract](../docs/src/advanced_config.md#L89) · [Digest comparison](../src/Simulations.jl#L347) · [Two-revision evidence](2026-11-25-pull63-contracts-codex-evidence/README.md)
3. **Major. A finite fallback can still stay stale when a previously used reference is restored.** The fresh transition from no reference to A is fixed. I started with A, ran without a reference while registering a new finite fallback, then restored the same A. Its record survives the intermediate run in `src/StatCalculation.jl:297–305`. The pipeline returned `:cached` and fallback 1. Forcing statistics gave 3. Both revisions exhibit the stale result. The new `_reference_change` branch treats the retained A record as authoritative even though the last evaluation ran without a reference. Refresh the affected values whenever their provenance is mixed, or keep provenance per statistic. [Reference check](../src/Simulations.jl#L441) · [Two-revision evidence](2026-11-25-pull63-contracts-codex-evidence/README.md)

## Earlier findings rechecked

- Unsupported scalar numbers, custom integers, an Int32 range, an array of Int32 static vectors, a nested BigInt and a set inside a pair are rejected. Int64 endpoints round-trip as parameters and dictionary keys. A sweep containing `1.5f0` and `1.5` errors with the parameter name. Identical values still deduplicate.
- The original metadata-edit case now preserves both records and re-registering L1 gives 6. Explicitly replacing the numerical solution clears the three statistics-evaluation records. A finite statistic from a fresh run without a reference now refreshes to 3 when a reference is added.
- Both #60 wording findings are resolved. The guide specifies the allowed key types and accepts valid renamed imports. The prior legacy-store example still keeps the valid file visible and usable. [Earlier whole-codebase report](2026-11-25-full-codebase-codex.md) · [Earlier #60 report](2026-11-24-pull60-identity-codex.md) · [Current evidence](2026-11-25-pull63-contracts-codex-evidence/README.md)

## Commands and results

I reviewed the complete #63 diff, including the docs and revised tests, and followed the affected code through task generation, store writes, reads and statistics. The four whole-file records use the earlier full-file reading and the intervening diff. Local checks used Julia 1.13.4 on Linux. Downstream applications and other operating systems were outside these runtime checks.

| Command | Result |
|---|---|
| `git diff HEAD^ HEAD --check` | No whitespace errors. |
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review` and `uvx --from aisignoff==0.20.1 aisignoff lint` | History enabled. 82 files and 10,436 lines declared. Five historical fallback warnings. |
| `JULIA_NUM_THREADS=2 julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | All 1,679 tests passed in 1m54.4s. |
| `julia -t 2 --project` with `parameters.jl`, `sources.jl` and `statistics.jl` | Ran on #63 and its first parent. Confirmed the supported controls, the save regression, and the persistent source and reference cases. |
| Prior scripts for metadata edits, renamed import and the legacy store | Confirmed the specified repairs. The legacy store was prepared before #58 and read on #63. |
| `uvx --from aisignoff==0.20.1 aisignoff report --html docs/src/assets/aisignoff.html --with-source`, `julia --project=docs -e 'using Pkg; Pkg.instantiate()'` and `julia --project=docs docs/make.jl` | Documentation built. Documenter skipped local deployment. |

[Exact evidence commands and captured outputs](2026-11-25-pull63-contracts-codex-evidence/README.md)

BLOCKING
