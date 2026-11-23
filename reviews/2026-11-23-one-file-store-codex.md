# Review of the one-file-per-simulation store

| | |
|---|---|
| Reviewed | 2026-11-23. #34 at `157a908eec396e46fa7a220e4e88097ae48b56e3`, first parent `1e72f3dfca6d1942a81daba6f4f5b80b93a33947`. The previous reviewed release was `8fdead725ef6898db6f199668d52af36f6272b72`, v0.7.1. |
| Reviewer | GPT Sol (OpenAI), independent session without the generating conversation. |
| Levels | A2 for #34, whose declared authoring model is Claude Opus, a different model in tier 2. A1 for the full snapshot, which contains Claude Fable-authored lines in tier 1. |
| Highest finding in #34 | Critical |

The storage redesign removes duplicate deletion and in-place rehash. All five v0.7.1 regression cases pass in the updated suite. Importing a real file written by the v0.7.1 release preserved the source bytes, field value and user metadata. Importing a malformed file or importing into a linked destination can still destroy a usable result. [Comparison output](2026-11-23-one-file-store-codex-evidence/current.txt) · [Legacy import](2026-11-23-one-file-store-codex-evidence/legacy.txt)

## Findings in #34

1. **Critical. Import with overwrite can replace a complete run with a file containing no simulation dataset.** At `src/DataManagement.jl:186` and line 222, the byte-copy path requires only that a `raw` key exists. I copied a valid file for field 7, replaced its `raw` entry with a string, and passed that copy to `import_sim_data(source; overwrite=true)`. The call reported one import and replaced the complete file. `does_sim_data_exist` then returned true and `load_sim_data(params)` returned a `String`. Validate the actual native dataset and its consistency with the file's parameters before replacing a usable run, including for byte-for-byte imports.
2. **Critical. A parameter-changing import follows a destination symlink and overwrites its external target.** At `src/DataManagement.jl:227`, the importer calls `_write_sim_file`, which resolves an existing destination through `realpath` at `src/IOUtils.jl:335`. I used a canonical path pointing to an external run with field 7. Importing field 9 with `remove_keys=[:obsolete], overwrite=true` left the link in place but replaced the bytes and field of its external target. The source file being read was untouched. Make import apply the same destination-link semantics to both its byte-copy and rewrite paths. Refuse linked destinations or explicitly replace the link itself, preserving its target.
3. **Major. An in-place batch can overwrite files in its own source list.** At `src/DataManagement.jl:210`, the alias check compares the destination only with the input currently being processed. In the documented mode that imports the active store, I put two matching runs in one directory, one with an extra key and field 9 and the other already at the canonical name with field 7. Removing the extra key with `overwrite=true` changed the latter input to field 9. The public contract says that the source is only read. Plan the batch first, check destinations against the full set of inputs and define how explicit overwrite interacts with input protection.
4. **Major. An import retry silently skips a partial destination.** At `src/DataManagement.jl:215`, matching parameters suffice to skip the import. I removed `raw` from a canonical file and imported a complete copy using default options. The result contained zero imports and the run remained unavailable. Distinguish an existing usable run from an incomplete destination and report recovery explicitly.
5. **Major. An exact import filter conflates Boolean and integer runs.** At `src/DataManagement.jl:200`, the filter uses `isequal`, so `filter_pairs=Dict(:k=>1)` imported both the integer run and the Boolean `true` run even though their hashes differ. Use the same canonical identity comparison for each normalized parameter value that storage uses.
6. **Minor. Saving over a dangling symlink removes the link.** At `src/IOUtils.jl:116`, `ispath` reports a missing target as a missing slot. Saving a dataset whose canonical path was a dangling link replaced it with a regular file without overwrite enabled. Treat an occupied link with an unreadable target as a distinct state and apply the documented refusal to replace it.
7. **Minor. Package metadata still identifies the breaking implementation as v0.7.1.** `Project.toml:3` and the generated documentation inventory say 0.7.1, while `docs/src/data.md:92` assigns hash format 4 to 0.8. The tagged 0.7.1 build uses format 3. A dependency accepting 0.7.1 can therefore also accept this untagged snapshot if supplied by path or revision. Keep the package and citation versions in sync with the breaking release identifier before tagging.

## Outside #34

**Critical. A deletion filter for integer `1` also selects the Boolean `true` run.** At `src/DataManagement.jl:78`, `delete_sim_data(Dict(:k=>1); dry_run=true)` selected both canonical paths. The same filter selected both in v0.7.1, which also used `isequal` for this comparison. A live deletion removes every selected file. Use type-aware matching consistent with storage in listing and deletion. [Current output](2026-11-23-one-file-store-codex-evidence/current.txt) · [v0.7.1 control](2026-11-23-one-file-store-codex-evidence/previous.txt)

## Scope and verification

The whole-file scope covers 60 files, including every Julia runtime, preset, test, fixture writer and documentation build script, plus project files, CI, configuration and documentation. I compared the previous snapshot, inspected all 11 changed files and traced their callers. Dependencies and compatibility bounds are unchanged. The whole-file scope excludes the historical review archive, binary fixtures, legal and branding assets. I checked the declarations separately and the tests exercised the fixtures. The tests ran on Linux with two Julia threads. Downstream integrations, other platforms, and simultaneous writes remain unverified.

| Command | Result |
|---|---|
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review` and `uvx --from aisignoff==0.20.1 aisignoff lint` | History enabled, review folder `reviews/`, no minimum. 81/81 files and 9537/9537 lines declared, with five pre-existing historical warnings. |
| `JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1 julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | Julia 1.13.4. 1490/1490 passed in 1m39.6s. |
| `julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, then `julia --project=docs docs/make.jl` | HTML built. Documenter skipped local deployment. |
| `julia --project -e 'using PDEStudioCore; set_save_path!(mktempdir()); c=test_heat_1d(); c.shared[:N]=8; c.shared[:T]=0.01; c.varied[:r]=[0.4]; set_stat_preset!("hyperbolic"); s=run_all_simulations(c; parallel=true,calculate_stats=true); @show length(s.ran) length(s.failed) length(s.stats_failed)'` | Three numerical methods ran with zero solver and statistics failures. |
| `julia -t 2 --project reviews/2026-11-23-one-file-store-codex-evidence/check.jl` | The [evidence directory](2026-11-23-one-file-store-codex-evidence/README.md) includes the exact commands for both versions and the real v0.7.1 seed case. |

BLOCKING
