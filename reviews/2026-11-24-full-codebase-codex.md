# Whole-codebase review of PDEStudioCore.jl 0.8.0

| | |
|---|---|
| Reviewed | 2026-11-24. `industrial-mathematics-group/PDEStudioCore.jl` on `main` at `feddb460d19502b6e3e2b90ccfd57a63be5a1cd3`. Its first parent and the previously reviewed code are `904535c180b9b157561156731685869d8a003bb6`. |
| Reviewer | GPT Sol (OpenAI), new session without the generating conversation. |
| Level | A1 for the package as a whole. The line declarations include Claude Fable (tier 1), above GPT Sol (tier 2). Ten complete files qualify for the requested A2 because their declared generating model is Claude Opus, a different tier-2 model. The record gives the level and highest finding for each file. |
| Highest whole-codebase finding | Critical |

Two independent operations lost stored data. One committed an incomplete rewrite after a JLD2 writer failed. Another applied a post-processor to a run outside the configuration. A parameter-changing import also reused a stale reference error, and two Float16 cases produced infinity for finite, representable results.

## Findings in the reviewed codebase

1. **Critical. Saving a run can discard a readable user entry after warning.** At `src/IOUtils.jl:354`, a failure to copy an unmanaged JLD2 entry is caught inside the loop. Line 361 still installs the incomplete file. I stored a calibration value of 47, made its custom writer fail while its reader continued to work, then called `save_sim_data(...; overwrite=true)` to save a metadata edit. The call logged a warning, returned the destination as usual and removed the calibration. Propagate the copy error so the existing outer cleanup discards the temporary file and preserves the original. Verify that a failed rewrite leaves the original bytes intact. [Output](2026-11-24-full-codebase-codex-evidence/entry.txt)
2. **Critical. A post-processor can overwrite a run outside its configuration.** At `src/Simulations.jl:441`, the write destination comes from the callback's mutable `sim_data.params`. I configured only `k=1`, with a separate stored run for `k=2`. Changing `data.params[:k]` to 2 and returning `true` made pass 3 replace the other run's field 2 with field 1. The summary reported success and the intended run had no post-processing record, so the callback remained eligible to run again. Capture the original task identity and reject a changed identity before saving. The check should leave both runs intact and surface the failure in the summary. [Output](2026-11-24-full-codebase-codex-evidence/check.txt)
3. **Major. Editing an imported parameter leaves reference-dependent statistics cached.** At `src/DataManagement.jl:265`, the importer changes the stored parameters and rewrites the old statistics along with the field. I imported a constant field of 1, changed `k=1` to `k=2` at the supported prompt, then ran the normal statistics pass with the same reference factory `p -> (_ -> p[:k])`. It reported a cache hit and kept the L1 error at 0. Forcing only the statistics on the same imported field gave 2, as expected on the two unit-spaced nodes. Invalidate registered statistics and their evaluation records when import changes the parameter identity, including whatever marker the next pass uses to decide whether to reuse a stored value. [Output](2026-11-24-full-codebase-codex-evidence/check.txt)
4. **Major. Eulerian Float16 spacing can overflow before division.** At `src/Constructors.jl:95`, the constructor subtracts the first coordinate from the last in the field precision. On `Float16[-40000, 0, 40000]` with constant field 0.25, it stored infinite spacing and the mass preset returned infinity. The Float64 control gave spacing 40000 and mass 30000 under the documented rectangle rule. Both are representable in Float16. Compute the difference and quotient in a wider type before converting the final spacing. The Eulerian resampling and reference-grid spacing formulas also warrant that treatment. [Output](2026-11-24-full-codebase-codex-evidence/check.txt)
5. **Major. The L2 preset overflows for an ordinary Float16 field magnitude.** At `presets/hyperbolic.jl:31`, the preset squares the field in its storage precision. On two unit-spaced nodes containing 300, the L2 norm was infinite. The same input in Float64 yielded 424.2640687, consistent with `sqrt(2) * 300` and well within Float16 range. Widen before squaring and summing, or use a scaled norm, and convert only the result to the dataset precision. The error presets use the same squaring pattern. [Output](2026-11-24-full-codebase-codex-evidence/check.txt)

## Comparison with the previous review

The only intervening commit, #40, added the previous review. The diff outside `reviews/` is empty. All five findings above concern code already present at the first parent. The findings line is for the requested whole-file scope. There is no product change to attribute to #40.

Two previously reported import behaviors remain reproducible. The source replacement during the second prompt still installs field 91 over field 7 if the replacement has the same parameters (**major**, `src/DataManagement.jl:253`). The broad change-detection promise in `docs/src/data.md:151` remains inaccurate (**minor**). Failure to create the destination directory still aborts the batch with `Base.IOError` (**minor**, `src/DataManagement.jl:248`). Pinning the source version and moving directory creation inside the per-file error handler address these separately. [Current rerun](2026-11-24-full-codebase-codex-evidence/prior.txt) · [Prior report](2026-11-23-checked-import-codex.md)

## Coverage and commands

I verified that every Git blob in the preceding 60-file package review matches this head. I carried forward that full-file reading and traced fresh cases through the public constructors, statistics, conversions, storage, import and batch APIs. The record covers all 36 Julia files, including solvers, tests and the docs build, plus the package docs and repository configuration. I checked `SIGNOFF.toml` and the line-level model declarations separately. Binary fixtures ran in the package suite. Historical reviews, legal text and branding assets are outside the package-code attestations. Local verification used Linux and Julia 1.13.4. I did not exercise downstream applications or other operating systems.

| Command | Result |
|---|---|
| `git diff HEAD^ HEAD -- . ':!reviews/**'` | Empty. The reviewed files match the preceding review by blob ID. |
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review`, `uvx --from aisignoff==0.20.1 aisignoff lint`, `uvx --from aisignoff==0.20.1 aisignoff report --json` | History enabled, review folder `reviews/`, no minimum. All 81 files and 9,765 lines declared. Lint listed five historical declarations that rely on file-level defaults. Checked the generating model in each file's line groups. |
| `JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1 julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | 1,528 of 1,528 passed in 1m30.4s. |
| `julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, then `julia --project=docs docs/make.jl` | HTML and version 0.8.0 inventory built. Documenter skipped local deployment. |
| `julia -t 2 --project -e 'using PDEStudioCore; set_save_path!(mktempdir()); c=test_heat_1d(); c.shared[:N]=8; c.shared[:T]=0.01; c.varied[:r]=[0.4]; set_stat_preset!("hyperbolic"); s=run_all_simulations(c; parallel=true,calculate_stats=true); @show length(s.ran) length(s.failed) length(s.stats_failed)'` | Three heat methods ran, zero solver failures and zero statistics failures. |
| `julia --project reviews/2026-11-24-full-codebase-codex-evidence/entry.jl` and `julia -t 2 --project reviews/2026-11-24-full-codebase-codex-evidence/check.jl` | Reproduced all five findings through public entry points. The JLD2 failure is injected. The numerical controls use the same inputs at higher precision. |
| `julia -t 2 --project reviews/2026-11-23-checked-import-codex-evidence/check.jl` | Reproduced the previous same-parameter replacement and directory-creation failures. |

[Evidence scripts, instructions and captured output](2026-11-24-full-codebase-codex-evidence/README.md)

BLOCKING
