# Independent review of checked imports in PDEStudioCore.jl

| | |
|---|---|
| Reviewed | 2026-11-23. #39 on `main` at `904535c180b9b157561156731685869d8a003bb6`, first parent `5e319e5cbaf9ff015dc798ec319ca81d708ab263`. The previous reviewed code was `338bcbb294d23faa85fe033e38531e975024d279`. Both snapshots declare package version 0.8.0. |
| Reviewer | GPT Sol (OpenAI), independent session without the generating conversation. |
| Levels | A2 for #39. Claude Opus and GPT Sol are different tier-2 models. A1 for the full snapshot because it also contains Claude Fable-authored lines in tier 1. |
| Highest finding in #39 | Minor |

#39 preserves the complete destination in the earlier malformed-source case. The old filter case allocates 50,752 bytes again, down from 16,422,000, and the documentation now describes ordinary saves through symlinks accurately. A valid replacement with matching parameters still gets installed. That behavior predates #39, which introduces the promise to detect changed sources. [Prior reproduction rerun](2026-11-23-checked-import-codex-evidence/prior-cases.txt)

## Findings in #39

1. **Minor. An unusable destination directory now throws out of the import batch.** At `src/DataManagement.jl:248` the new staging flow calls `mkpath(dir)` before entering the per-file `try` block. I configured a save root, then replaced its empty `data` directory with a regular file. Importing a valid result from another folder now raises `Base.IOError`. The previous implementation reported the failed write and returned an empty result vector. The source remained intact in both runs. Put destination directory creation inside the per-file error handler or document a deliberate change to the function's error behavior. [Current output](2026-11-23-checked-import-codex-evidence/current.txt) · [Previous output](2026-11-23-checked-import-codex-evidence/previous.txt)
2. **Minor. The new source-change guarantee is broader than the checks.** `docs/src/data.md:151` and `src/DataManagement.jl:157` say a changed source is reported and its destination left alone. At `src/DataManagement.jl:252` the code accepts any staged copy that holds a consistent dataset and has the planned parameter encoding. Changing the solution while keeping its parameters passes, as shown in the next section. Document precisely which changes are detected or pin the source version in the plan and verify the staged bytes against it. [Reproduction commands](2026-11-23-checked-import-codex-evidence/README.md)

## Outside #39

**Major. Interactive import can silently install a newer source version.** I started with a source and a destination both holding field 7. At the second source prompt I replaced the first source with a complete version holding field 91 for the same parameters. Both snapshots reported two imports and left field 91 in the first destination. #39 validates the installed file's structure and identity, which fixes the malformed-source case. It still permits changes to the solution and metadata between the prompt and the copy. A pinned source version would make the prompts refer to a stable dataset. [Paired results](2026-11-23-checked-import-codex-evidence/README.md)

## Scope and commands

I compared the 60-file whole-codebase scope with the previous review. Fifty-five files are byte-identical. I inspected all five changed files and traced their callers in the storage and simulation pipeline. The scope includes all 36 Julia files, including tests, the fixture writer and the docs build script, as well as the repository docs, projects and configuration. Dependencies and compatibility bounds are unchanged. Historical review artifacts, legal and branding files, and binary fixtures are outside the whole-file records. Tests exercised the shipped fixtures. I checked the model declarations separately. Local verification used Linux with two Julia threads. Downstream applications and other platforms remain unverified. The source replacement occurred in a controlled prompt callback.

| Command | Result |
|---|---|
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review` and `uvx --from aisignoff==0.20.1 aisignoff lint` | History enabled, review folder `reviews/`, no minimum. Lint validates all 81 files and 9,765 lines with five pre-existing historical warnings. |
| `JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1 julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | Julia 1.13.4. 1,528 of 1,528 tests passed in 1m27.2s. |
| `julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, then `julia --project=docs docs/make.jl` | HTML built with inventory version 0.8.0. Documenter skipped local deployment. |
| `julia --project -e 'using PDEStudioCore; set_save_path!(mktempdir()); c=test_heat_1d(); c.shared[:N]=8; c.shared[:T]=0.01; c.varied[:r]=[0.4]; set_stat_preset!("hyperbolic"); s=run_all_simulations(c; parallel=true,calculate_stats=true); @show length(s.ran) length(s.failed) length(s.stats_failed)'` | All three methods ran with zero solver and statistics failures. |
| `julia -t 2 --project reviews/2026-11-23-checked-import-codex-evidence/check.jl` | Repeated both cases on the preceding snapshot. The [evidence instructions](2026-11-23-checked-import-codex-evidence/README.md) include the exact control and the previous review command. |

CHANGES SUGGESTED
