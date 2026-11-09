# Review: PDEStudioCore.jl — fixes of reviews/a42a9e0.md (ef56ddf)

Reviewer: Claude Opus 5.5 (Anthropic), new session without the generating conversation

## Scope

I did a narrow re-review of `git show ef56ddf` (src/IOUtils.jl, src/Simulations.jl, src/DataManagement.jl, docs/src/{advanced_config,data}.md, test/test_data.jl, test/test_pipeline.jl), checking it against findings F1–F6 and minor issues 1–7 of `reviews/a42a9e0.md`. Beyond that I attacked these changes:
- the `:outdated` outcome;
- the same-data detection in `save_sim_data`;
- provenance on new files;
- the `nothing` metadata rule;
- the `_func_*` helpers;
- `_raw_loads` / `_format_version`;
- the `param_` prefix in `sim_data_table`.

Nothing in the repositories was edited. I removed the temporary a42a9e0 worktree (`$R/old`) and the docs clone. `$R/repo` is clean.

## Tests run

| Run | Result |
|:--|:--|
| Full suite `-t 8` at ef56ddf (`probes/suite_t8.log`) | 1293/1293 pass, 1m05s |
| Full suite `-t 1` (`probes/suite_t1.log`) | 1293/1293 pass, 1m07s |
| ef56ddf `test/` with a42a9e0 `src/` (worktree; `probes/suite_newtests_oldsrc.log`) | exit 1: 1275 pass, 11 fail, 5 errors. All new testsets fail: format-version user entry, dry-run version-0, `upgrade_sim_data` dry-run unreadable, provenance kept after `add_stat!`, new-file provenance, `param_file`, `:outdated` + warning, callable objects. Two new assertions (test_data.jl:457, :466) also pass on old src (they guard against regressions). |
| Docs: throwaway clone, origin set to GitHub, own docs env, `docs/make.jl` (`probes/docs_build.log`) | builds, exit 0; no missing docstrings or broken refs; deployment skipped (not CI) |
| Test env resolves PDEStudioCore to | `$R/repo/src/PDEStudioCore.jl` (checked) |

Probes from the previous review, rerun on ef56ddf (`$R/repo/reviews/a42a9e0/`):

| Probe | Before (a42a9e0) | Now (ef56ddf) |
|:--|:--|:--|
| `probe_post_nonidempotent.jl` | u 2 → 4 after a comment-only edit, → 8 without record | u stays 2 after the edit (kept, `:outdated`); → 4 only for a file without record, which is now documented |
| `probe_callable.jl` | solver task failed, post-processor threw | solver ran=1, failed=0; post `:ran => 1` |
| `probe_callable_old.jl` | false / threw MethodError | true / ok |
| `probe_record_writers.jl` | same-data save dropped solver, wall time and record; post-processor reran; `calculate_all_stats!` file had no provenance; `nothing` dropped | solver, wall time and record kept; no rerun; provenance present; `note => nothing` stored |
| `probe_table.jl` | `file`/`solver`/`kind` columns overwritten | `param_file`, `param_kind`, `param_solver` columns; fixed columns correct; version-0 omission now documented |
| `probe_dryrun.jl` / `probe_dryrun_stats.jl` | dry and real runs differed | dry = real (`ran=1 cached=3`, same stats and post counts); `upgrade_sim_data(dry_run)` says `unreadable`, like the real call; nothing written |
| `probe_index_stale_dup.jl` | older duplicate returned | unchanged behaviour, now documented (data.md, IOUtils comment) |
| `probe_solver_version.jl`, `probe_tidy_tmp.jl`, `probe_summary_parallel.jl` (`-t 1`, `-t 8`) | ok | still ok (no regression from `_func_version`) |

New probes (`$R/probes/`):

| Probe | What it checks | Result |
|:--|:--|:--|
| `probe_outdated.jl` | `:outdated` with `:ignore`/`:warn`/`:recompute`, dry run, force + dry, two configs with different post-processors | `:ignore` and `:warn` → `:outdated` + warning; dry run → `:outdated` + warning, summary "1 outdated"; `:recompute` → `:ran` on new data; force + dry → `:ran`; alternating configs → the post-processor is applied 3 times to the same data (Finding 2) |
| `probe_save_same.jl` | stats-only post-processor (the docs' `add_maximum` pattern) followed by a hand recompute + `save_sim_data(overwrite)`; cost on a 61 MB file | the record is kept, the post-processor's statistic is lost and the next run skips (Finding 1); the comparison costs 0.01 s of a 0.06 s save (negligible) |
| `probe_func_helpers.jl` | named, anonymous, closure, parametric functor, builtin, intrinsic, type, package function, `ComposedFunction` | never throws; a type used as solver is recorded as `"DataType"` in package `Core`, with no version (Minor 1) |
| `probe_table_prefix.jl` | parameters `file` and `param_file` both present; 0.4 user entry `format_version = 7` / `"user value"` | `param_file` shows `"mesh.msh"` and `"other.cfg"` is lost (Finding 3); 7 counts as version 7, so `upgrade_sim_data` says `:current` and never adds `dim_keys`; `"user value"` is overwritten by 2 (Minor 2) |
| `probe_writers2.jl` | provenance through the conversion cache, rehash to a new name, upgrade of a version-0 file; `nothing` via `run_smart_simulation` | provenance kept by cache and rehash; upgraded file has no provenance (Minor 3); `nothing` stored |

## Findings

### 1. `save_sim_data(overwrite = true)` of a fresh recomputation keeps the post-processing record, but the post-processor's statistics are gone (low, CONFIRMED)

- **Where:** src/IOUtils.jl `save_sim_data` (`same = … _is_native_representation(path, sim_data)`), together with `_same_solution`, which ignores statistics by design.
- **What:** "Same data" is decided only by representation, shape and solution (`u`, axes / `t`, `x`). The `add_stat!` case it is meant for is handled correctly. But a dataset recomputed by hand with a deterministic solver has the same `u` and lacks the statistics the post-processor added. It counts as "same", so `"postprocessed"` is kept and the next pipeline run reports `:skipped`. The post-processor's statistic is then missing until `force_postprocess`.
- **Why it matters:** The docs now recommend exactly this kind of post-processor for idempotence ("set a statistic rather than accumulate into the solution"; the `add_maximum` example).
- **Evidence:** `probe_save_same.jl` (a):
  - after the pipeline: stats `[:Solution, :maximum]`;
  - after `save_sim_data(lin_solver(p); overwrite = true)`: stats `[:Solution]`, record = `add_max`;
  - next run: `post = Dict(:skipped => 1)`, stats `[:Solution]`, calls = 1.
- **Fix:** Keep the record only when the new data also contains the stored statistics, e.g. require `issubset(stored "stat_keys", keys(sim_data.stats))` in addition to `_is_native_representation`. The stat keys can be read from the metadata, without loading. Otherwise keep the provenance but drop `"postprocessed"`.
- **Test:** stats-only post-processor; `save_sim_data(solver(p); overwrite = true)`; the next run reports `:ran` and `:maximum` is back.

### 2. "Runs once per dataset and name" does not hold when two post-processors alternate on the same data (low, CONFIRMED)

- **Where:** src/Simulations.jl `_post_task` / `_postprocess_record`. A file holds a single `"postprocessed"` record, the last one.
- **What:** `postprocess` is not part of the parameter hash. Two configurations with the same tasks and different post-processors therefore share the files, e.g. a script and a PDEStudio session, or a config edited back and forth. Each run replaces the record with its own name, so switching back re-applies the first post-processor to data it has already processed. The commit message says "a post-processor runs once per dataset and name". The docs say "runs once per dataset: on new data, and with a post-processor of another name", which suggests the same.
- **Evidence:** `probe_outdated.jl`: alternating `cfg2` (`other_post`) and `cfg` (`inc_post`, adds 1) twice → `inc_post` applied 3 times to the same data (u = 1 → 4).
- **Fix:** Either store the records per name (e.g. `"postprocessed" => Dict(name => record)`; the table shows the names), or state in the docs and docstring that only the last post-processor is remembered, so switching between post-processors re-applies them.
- **Test:** two configs alternating; the second run of the first config reports `:skipped`.

### 3. `sim_data_table`: the `param_` prefix can collide with a real parameter, and a value is silently lost (low, CONFIRMED)

- **Where:** src/DataManagement.jl `sim_data_table`: `row[key in fixed ? Symbol("param_", key) : key] = v`.
- **What:** If parameters `file` and `param_file` (or `solver` and `param_solver`) both exist, both write the column `param_file`. Which value survives depends on Dict iteration order, and the other is dropped without a warning.
- **Evidence:** `probe_table_prefix.jl`: parameters `file = "mesh.msh"`, `param_file = "other.cfg"` give the columns `[…, "n", "param_file", "sim_func_name"]`, and `param_file = "mesh.msh"`; `"other.cfg"` is gone.
- **Fix:** Prefix again while the name is taken (`param_param_file`), or error or warn on the collision. Mention it in the docstring.
- **Test:** parameters `:file` and `:param_file` together; both values appear.

### 4. `on_changed_sources = :ignore` does not silence the new `:outdated` warning (low, CONFIRMED)

- **Where:** src/Simulations.jl pass 3. The record includes the source digests whatever `on_changed_sources` is.
- **What:**
  - With `:ignore` ("keeps them silently", docs and docstring), any source edit, including one unrelated to the post-processor, makes every dataset `:outdated`.
  - The run warns on every call until `force_postprocess`. Forcing re-applies the post-processor to all data, which is exactly what a user of a non-idempotent post-processor wants to avoid.
  - So the only way to stop the warning carries the risk the docs warn about.
- **Evidence:** `probe_outdated.jl`: `ignore post=Dict(:outdated => 1) changed=0 warnings=1 outdated-warning=true`.
- **Fix:** With `:ignore`, compare the record without `"sources"` (still compare the name and package version). Alternatively, document that `:ignore` only covers the solver results.
- **Test:** source edit with `:ignore` → `:skipped`, no warning.

No high or medium findings. I found no problem in:
- the `:outdated` / `force_postprocess` / `:recompute` / `dry_run` interplay (all consistent with the real run);
- the summary text ("1 outdated");
- the same-data cost;
- params normalisation (`_find_file` and `_save_sim_data` both hash `_normalize_params`);
- converted or reference datasets (different representation or solution → new provenance, as documented);
- errors in the comparison (caught → treated as new data);
- provenance through the conversion cache, rehash and `_update_entries!`.

## Per-item status of reviews/a42a9e0.md

| Item | Status | Notes |
|:--|:--|:--|
| F1 non-idempotent post-processor reapplied | **Fixed** (by design change) | Same-name records are no longer reapplied (`:outdated` + warning); idempotence advice is back in the docs and docstring; files without a record documented. Residual gaps: Findings 2 and 4. |
| F2 callable objects | **Fixed** | `_func_*` helpers never throw; test added and it fails on a42a9e0. Residual: type as solver (Minor 1). |
| F3 same-data save drops record; `calculate_all_stats!` file without provenance | **Fixed** | Both verified. Residual wrong positive: Finding 1. |
| F4 parameter names overwrite fixed columns | **Fixed, partly** | Prefix works; prefix collisions lose values (Finding 3). |
| F5 data folders shared with 0.4 | **Fixed** (docs note) | Note is accurate (matches the previous review's probe). |
| F6 dry run ≠ real run | **Fixed** | Version-0 and unreadable files and the empty registry are now classified like the real run. The empty-registry branch has no test. |
| Minor 1 index wording | Fixed | data.md and code comment describe the stale-duplicate case. |
| Minor 2 dry run includes sources | Fixed | docs and docstring. |
| Minor 3 RunSummary `:ignore` | Fixed | |
| Minor 4 table skips version-0 | Fixed | docstring. |
| Minor 5 `_format_version` user entry | **Partly** | Non-integers are ignored. A user Integer ≥ 2 still counts, and the user value is overwritten on upgrade (Minor 2 below). |
| Minor 6 git commit note | Fixed | "uncommitted changes are not recorded". The global-environment case (an unrelated repository) is not mentioned. |
| Minor 7 `nothing` metadata | Fixed | User `nothing` values are stored; only record keys are dropped (probes). |

## Test coverage

The new tests are meaningful and fail on a42a9e0 src. Still uncovered:
- F6's empty-registry branch (`isempty(required) ? :cached`);
- user `nothing` metadata being stored;
- `:outdated` in a dry run and with `:ignore`;
- Findings 1–3;
- a type or closure as solver.

## Minor issues

1. **Type as solver** (`const s = MyPkg.MyType`, which is resolvable since `resolve_dynamic_function` returns any global): `_func_name` gives `"DataType"` and `_func_package` gives `Core`. The provenance names the wrong solver, and changes of the package version are never detected. Fix: `f isa Union{Function, Type} ? nameof(f) / parentmodule(f) : … typeof(f)`. Closures and anonymous functions record `"#5"`-style names, which is acceptable for provenance.
2. **`_format_version`:** a 0.4 user entry `format_version` that is an Integer ≥ 2 still counts, so such files are `:current` and never get `dim_keys`/`time_dim`. Any other user value is silently overwritten by `upgrade_sim_data`, and the new test (test_data.jl:335–337) does this without comment. A warning naming the overwritten value would be kind; checking `haskey(f, "dim_keys")` alongside the version would close the first case.
3. **advanced_config.md:** "Every data file also records its provenance". Upgraded version-0/1 files (and files rewritten from them) have none. Say "every file written since …".
4. **Docs pin release numbers:** "Files written before PDEStudioCore 0.5 have no record"; `Project.toml` is 0.4.4. That holds only if the release becomes 0.5, which is the user's decision. The breaking `RunSummary` return type makes 0.5 likely; keep the wording in sync if not.
5. **`save_sim_data`:** `try _is_native_representation(…) catch; false end` also swallows `InterruptException`. Harmless, but other places rethrow it.

## Verdict

The fix commit resolves all six findings of `reviews/a42a9e0.md`; F4 is only partly fixed and the follow-up is Finding 3. Of the minor issues, six are fixed and Minor 5 is partly fixed. Tests pass at `-t 1` and `-t 8` (1293/1293), the new tests fail on the old src, and the docs build. What remains are narrow edge cases in the new record logic and the table prefix, none of which loses solver results. Findings 1 and 2 can make a post-processor's effect go missing or be applied repeatedly, so they deserve a fix or a docs sentence before release.

Ready to merge after deciding on Findings 1–4 (fix or document).

Counts: 0 high, 0 medium, 4 low (all CONFIRMED with probes in `$R/probes/`), 5 minor.
