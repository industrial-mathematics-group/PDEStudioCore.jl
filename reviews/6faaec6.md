# Review: PDEStudioCore.jl — metadata field (6faaec6)

Reviewer: Claude Opus 5.5 (Anthropic), new session without the generating conversation

## Scope

I reviewed `git show 6faaec6` on top of e1c864d (src/IOUtils.jl, DataManagement.jl, Simulations.jl, StatCalculation.jl, SimData.jl, Constructors.jl, ConversionUtils.jl, docs/src/{data,advanced_config}.md, the tests and the v0.4 fixtures). Areas I tried to break:
- **Reading 0.4.4 files of every kind.** I wrote them with a worktree of `origin/main_dev` (2818d7e) in a temporary env.
- **Mixed writers:** 0.4 reading and rewriting v3 files, and v3 reading unreleased v2 files from e1c864d.
- **Cost of the Upgrade path** on large datasets.
- **`_write_dataset!`** under concurrency.
- **Metadata through every writer:** save, `run_smart_simulation`, statistics, post-processing (true and false), rehash, conversion cache, upgrade.
- **`_file_metadata` on legacy files**, `load_sim_data(prefix)`, `sim_data_table`.
- **Downstream:** PDEStudio, HyperCloud and HyperCloudCore.
- **Docs.**

I edited nothing in the repositories. I removed my temporary worktrees, the docs clone and the temporary env afterwards. Probes and logs are in `/home/agent/.claude/jobs/d2d299f1/tmp/review-meta1/probes/` (written as `$R/probes` below). The 0.4/v3/v2 test data folders (`$R/d04`, `$R/dmx`, `$R/dv2`) are kept.

## Tests run

| Run | Result |
|:--|:--|
| Full suite `-t 8` at 6faaec6 (`probes/suite.log`) | 1307/1307 pass, 1m06s |
| Full suite `-t 1` (`probes/suite_t1.log`) | 1307/1307 pass, 1m07s |
| 6faaec6 `test_pipeline.jl` + `test_data.jl` with e1c864d `src/` (worktree) | 284 pass, 11 errors. Every changed or new testset fails: 0.4 fixtures, provenance/own metadata, prefix loading, sources, post-processing record, callable objects |
| Docs: throwaway clone, origin set to GitHub, own docs env, `docs/make.jl` | builds; no warnings apart from "skipping deployment" |
| Test env resolves PDEStudioCore to | `$R/repo/src/PDEStudioCore.jl` (checked) |
| JLD2 compat `0.6, 1`: is `typemap` as a function, plus `Upgrade`/`rconvert`, available at the lower bound? | yes, checked in the JLD2 v0.6.0 source |

| Probe | What it checks | Result |
|:--|:--|:--|
| `w04.jl` (0.4.4) → `r04.jl` (6faaec6) | 8 legacy files: Eulerian transient with user entries + stats + `conv_L` + `conv_E`; static 2-D Float32 with M=5; static and transient (Float32) Lagrangian with `conv_E`; user entries `format_version`/`provenance`/`postprocessed` + a group; user entry `"metadata"`; a version-0 data-only file; a pipeline file with `sources` | 7/8 load with the right types and metadata; conversions carry the metadata; the pipeline uses them as they are (no file written); upgrade OK for 7. **File 6 (user `"metadata"` entry) fails everywhere** (F1). Groups via prefix load: **closed file** (F2) |
| `w3.jl` → `rw04.jl` (0.4.4) → `r3after.jl` | 0.4 on a v3 file: exists, load, `conv_L`, stats pipeline, `force_overwrite`; then v3 reads back | 0.4 reads v3 datasets (JLD2 drops the extra field). After the 0.4 rewrite, v3 reads the data. Stale `"metadata"` (`:marked`, `:postprocessed`) is kept as documented, and post-processing reports `:skipped` |
| `big.jl` | plain `jldopen` vs `_open_data` (typemap) vs `load_sim_data`, on 49 MB Eulerian and 115 MB Lagrangian files | identical allocations (49.1 / 116.5 MiB, no extra copy); time 0.006/0.006 s (E), 0.017/0.026 s (L) |
| `race.jl` (`-t 4`) | a reader and a writer on `d.metadata` during `_save_sim_data` | the reader saw an empty dict 615,890 times; 5 of 5 concurrent writes lost (F4) |
| `wbig04.jl` → `rbig04.jl` | 0.4 file with a 76 MB user entry: load, table, post-processing with a `nothing` return | every load and table call reads 76.5 MiB; the record update grows the file from 76.3 to 152.6 MiB (F5) |
| `wv2.jl` (e1c864d) → `rv2.jl` | unreleased v2 file (String-keyed provenance and record) | post-processing reports `:outdated` + warning; table `solver`/`wall_time` missing (F6) |
| `del.jl` | `delete!(d.metadata, k)` or `d.metadata = Dict(...)`, then `save_sim_data(overwrite = true)` | the deleted keys come back (F3) |
| `collide.jl` | top-level JLD2 entry `"note"` in a v3 file whose metadata has `:note`; rewrite of the same data | `"note"` dropped, `"other"` kept (F7) |
| `newdata.jl` | new data saved over a file with user metadata | only `[:provenance]` is left (F8, docs) |
| `conv.jl` | conversion cache and rehash | `conv_L` stores a full copy of the metadata (F8); rehash keeps `[:note, :provenance]` |
| `grp.jl`, `grpprev.jl` | `load_sim_data(prefix)` on a file with a group, e1c864d vs 6faaec6 | e1c864d: `"grp/a" => 1`. 6faaec6: `"grp" =>` a Group whose file is closed (F2) |
| `f6.jl` | pipeline on 0.4 file 6 | `exists true`, task **failed** every run: MethodError (F1) |
| `statpost.jl` (6faaec6 and e1c864d) | `calculate_all_stats!` of a recomputed same-solution dataset after a stat-adding post-processor | the record is kept, the stat is lost, the next run skips. Same on e1c864d, so not a regression (Minor 1) |
| `plain.jl` | `JLD2.load` of a 0.4 dataset with the new code | `JLD2.ReconstructedMutable{…}` (Minor 4) |

## Findings

### 1. A 0.4 file with a user entry named `"metadata"` can't be loaded, fails its pipeline task on every run, and breaks `sim_data_table` for the whole folder (medium, CONFIRMED)

- **Where:** src/IOUtils.jl `_file_metadata`: `haskey(file, "metadata") && return _metadata_dict(file["metadata"])`. It is used by `_load_key`, `load_sim_data(prefix)`, `sim_data_table`, `_code_changed`, `_post_task` and `_carry_metadata!`.
- **What:** 0.4 did not reserve `"metadata"`: `save_sim_data(d; metadata = Dict("metadata" => …))` and direct JLD2 writes were both allowed. The new code takes any `"metadata"` entry as the dataset's field, regardless of the format version:
  - **A non-dict value throws** `MethodError: no method matching _metadata_dict(::String)`. `load_sim_data(p)` fails. `does_sim_data_exist` is true (a v1 file is "current"), so the pipeline neither uses nor recomputes the file: the task is reported as failed on every run. `sim_data_table()` throws for the entire data folder, because there is no per-file guard. `upgrade_sim_data()` says `:unreadable`, while `upgrade_sim_data(dry_run = true)` says `:upgraded`, because `_raw_loads` doesn't read the metadata. The docstring promises that the pipeline recomputes `:unreadable` files, which isn't true here.
  - **A Dict value** silently replaces every other legacy entry. `"sources"` is not read, and `upgrade_sim_data` then drops it (a legacy key).
- **Evidence:** `r04.jl`: `load 6` FAIL, `table` FAIL, `after upgrade load 6` FAIL, dry run `:upgraded => 8` vs real run `:upgraded => 7, :unreadable => 1`. `f6.jl`: `RunSummary: 0 ran, 0 cached, 1 failed — MethodError …`.
- **Fix:**
  - Treat `"metadata"` as the field only when `_format_version(file) >= 3`. For older files, read it as a user entry like the others (`:metadata => value`).
  - Because `_update_metadata!` writes `"metadata"` into v1 files (post-processing, `nothing` return), it must then also mark the file as v3. Either upgrade the file first, which also fixes F5, or write `"format_version"` together with it (v1 files of 0.4.4 already have `dim_keys`).
  - Guard each file in `sim_data_table` (`try … catch` → `missing` columns).
- **Test:** a fixture (or a file written with JLD2 directly) with `"metadata" => "x"`. Check: it loads with `metadata[:metadata] == "x"`, `sim_data_table()` works, and the pipeline reports it as cached.

### 2. `load_sim_data(prefix)` returns groups as `JLD2.Group`s of a closed file (low, CONFIRMED, regression)

- **Where:** src/IOUtils.jl `load_sim_data(hash_prefix; key = nothing)`: `Dict(k => file[k] for k in keys(file))`.
- **What:** e1c864d used `JLD2.load(path)`, which flattens groups into `"grp/a" => 1`. The new comprehension returns `"grp" => JLD2.Group`, and the file is closed by the time the caller gets it. The docs say the function "returns the Dict of all stored entries", and the storage docs explicitly mention groups the user stored.
- **Evidence:** `grpprev.jl`: e1c864d `["…", "grp/a", "grp/b", …]`, `grp a: 1`; 6faaec6 `["…", "grp", …]`, `ArgumentError: file is closed`.
- **Fix:** recurse into groups and emit `"grp/sub"` keys, as `JLD2.load` does.
- **Test:** a file with a group; `load_sim_data(prefix)["grp/a"] == 1`.

### 3. A metadata entry can't be removed: a same-data save brings back every stored key the dataset doesn't have (medium, CONFIRMED)

- **Where:** src/IOUtils.jl `_carry_metadata!`, called from `_new_or_same_data!` (`save_sim_data`) and from `_calculate_all_stats!`.
- **What:** `data.metadata` is documented as the dataset's own dict, and the documented workflow is `data.metadata[:note] = …; save_sim_data(data; overwrite = true)`. But after `delete!(d.metadata, :secret)`, or `d.metadata = Dict(:only => 1)`, saving the same data merges every stored key back in. There is no public way to remove a wrong flag, path or token. The behaviour is also inconsistent: a post-processor that deletes a key and returns `true` does remove it, because that path writes with `_save_sim_data` directly.
- **Evidence:** `del.jl`: after `delete!` + save: `[:note, :provenance, :secret]`; after replacing the dict + save: `[:note, :only, :provenance, :secret]`.
- **Fix:** A dataset loaded from the file already holds its metadata, so carrying is only needed for fresh recomputations of the same solution. Restrict `_carry_metadata!` to the pipeline keys (`:provenance`, `:sources`, `:postprocessed`, when absent). Alternatively carry only when the dataset's metadata is empty, and document that.
- **Test:** `delete!` + `save_sim_data(overwrite = true)` → the key is gone after loading. A fresh same-solution recomputation still keeps `:provenance`.

### 4. `_write_dataset!` empties the caller's `metadata` during the write (low, CONFIRMED)

- **Where:** src/IOUtils.jl `_write_dataset!` (`setfield!(data, :metadata, Dict())` … `finally` restore).
- **What:** For the length of the JLD2 write, the caller's object has an empty metadata dict:
  - Another task reading `d.metadata` sees it empty.
  - A write into it lands in the temporary dict and is lost.
  - Two concurrent saves of the same object can interleave so that the second "restores" the first one's empty dict, and the file of the second gets empty metadata (it reads `data.metadata` in `_write_sim_file` before swapping).

  Exceptions are handled correctly (`finally`).
- **Evidence:** `race.jl` (`-t 4`, 300×300×10 grid): the reader saw an empty dict 615,890 times; 5 of 5 concurrent `d.metadata[:flag] = i` writes were lost.
- **Fix:** Store a shallow copy instead of mutating the caller's object, e.g. `ESimData{D,DS,M,T}(d.params, d.domain, d.axes, d.u, _raw_stats(d))`. The inner constructor doesn't copy the arrays (the `convert`s are no-ops); it only copies the params and stats dicts.
- **Test:** check `d.metadata` from a second task during a save of a large dataset; the dict is never empty.

### 5. Legacy files: every top-level user entry is read as metadata on every access, and record updates duplicate them (low, CONFIRMED)

- **Where:** `_file_metadata` (legacy branch), `_update_metadata!`, `sim_data_table`.
- **What:** For 0.4 files, all non-managed top-level entries become metadata. Large entries (e.g. a reference field stored with `save_sim_data(...; metadata)`, which 0.4 never loaded with the data) are now read by:
  - every `load_sim_data`;
  - every `sim_data_table` row (its docstring says "only the lightweight metadata of each file is read");
  - `_code_changed` and `_post_task`.

  `_update_metadata!` (post-processing, `nothing` return) writes all of them into a new `"metadata"` entry and leaves the originals in place. Because `_update_entries!` doesn't reclaim space, each further record update (another post-processor name, `force_postprocess`) adds another full copy.
- **Evidence:** `rbig04.jl`: `load_sim_data` 76.5 MiB allocated (0.2 MiB without the entry); `sim_data_table` 76.5 MiB; file 76.3 → 152.6 MiB after one post-processing run.
- **Fix:** In `_update_metadata!`, upgrade a legacy file first (one rewrite; after that, record updates are small). This also covers the F1 marker. Optionally document that metadata is meant to be small.
- **Test:** a legacy file with a large user entry; post-processing with a `nothing` return; the file size stays about the same.

### 6. Unreleased v2 files (written from this PR branch) report their post-processing as outdated (low, CONFIRMED)

- **Where:** `_file_metadata` legacy branch, `_post_task`, `sim_data_table`, `_code_changed`.
- **What:** v2 files store `"provenance"` and `"postprocessed"` with String keys, and records with `"name"`. These are taken over verbatim:
  - Records never equal the new Symbol-keyed ones, so every run reports `:outdated` with a warning.
  - `get(prov, :solver)` and `get(prov, :wall_time)` give `missing` in the table.
  - The solver-version check in `_code_changed` is silently off.
  - `upgrade_sim_data` (v2 < 3) preserves the String keys forever.
- **Evidence:** `rv2.jl`: `Dict(:outdated => 1)` + warning; table `(Any[2], Any[missing], Any[missing], Any["noop2"])`.
- **Fix:** Normalise `:provenance` and `:postprocessed` records to Symbol keys (dropping `"name"`) when reading legacy entries. Or, since v2 was never released, state that such data has to be recomputed or post-processed again with `force_postprocess`.
- **Test:** a v2-style file built with JLD2; the next run reports `:skipped`.

### 7. A top-level entry the user wrote with JLD2 is dropped on rewrite if a metadata key has the same name (low, CONFIRMED)

- **Where:** src/IOUtils.jl `_write_sim_file`, the carry loop: `haskey(md, Symbol(k)) && continue  # (the last: read into the metadata)`.
- **What:** The skip is meant for legacy files, whose top-level entries were read into the metadata. It also applies when `previous` is a v3 file, where those entries are not metadata. This contradicts data.md: "Other entries (e.g. written with JLD2 directly) are kept when the data is rewritten."
- **Evidence:** `collide.jl`: `(haskey "note", haskey "other") == (false, true)` after `add_stat!` + `save_sim_data(overwrite = true)`.
- **Fix:** apply that condition only when `previous` has no `"metadata"` entry (format < 3).
- **Test:** the probe as a test.

### 8. Docs and docstrings out of step with the behaviour (low, CONFIRMED)

- **advanced_config.md:73** still says the source digests are stored "in each newly written data file (entry `"sources"` …)". They are now in `data.metadata[:sources]`.
- **New data and user metadata.** data.md ("New data gets a new provenance and loses `:sources` and `:postprocessed` of the data it replaces") and the `save_sim_data` docstring read as if user entries survive new data. In fact all stored metadata is replaced (`newdata.jl`: only `[:provenance]` remains). In 0.4, user entries survived rewrites with new data, so this is a behaviour change worth one sentence.
- **"Stored once".** data.md's storage table says `"metadata"` is "stored once … `"raw"` holds the dataset without it". Conversion caches written by `_append_key!` store a full copy (`conv.jl`: `conv_L` holds `[:note, :provenance]`). This is harmless, since `_load_key` overrides it, but either strip it with `_write_dataset!` or adjust the sentence.
- **`sim_data_table` docstring:** "only the lightweight metadata" (see F5).
- **`upgrade_sim_data` docstring:** ":unreadable … the pipeline recomputes them" doesn't hold for v1 files (F1).

## Test coverage

The new tests are meaningful. They fail on e1c864d's src (11 errors), and the fixtures check hash stability against 0.4 as a side effect. Still uncovered:
- 0.4 files that are static, Float32, M>2, static Lagrangian, or have groups or user entries named like current keys (`"metadata"`, `"provenance"`, `"format_version"`) (F1);
- the `evaluated_stats`/`evaluated_with_reference` carry through upgrade;
- a version-0 data-only 0.4 file through the Upgrade path;
- a 0.4 writer rewriting a v3 file, which the commit claims to support; only the fixtures' read path is tested;
- `load_sim_data(prefix)` with groups (F2);
- deleting metadata (F3);
- the `_update_metadata!` false path on a legacy file (F1, F5);
- `_write_dataset!` leaving the caller's object untouched (F4);
- v3 entry collisions (F7).

## Minor issues

1. **Pre-existing, same on e1c864d:** `calculate_all_stats!` of a recomputed same-solution dataset keeps `:postprocessed` although the post-processor's statistics are gone. The next run skips post-processing and the stat is lost (`statpost.jl`). data.md claims the issubset rule for "statistics" rewrites too. The new `_carry_metadata!` line in `_calculate_all_stats!` is where to add `issubset(_stored_stat_keys(path), keys(sim_data.stats)) || delete!(md, :postprocessed)`.
2. **Stale legacy entries survive as top-level junk.** When new data, or a post-processor that deleted a legacy key, rewrites a v1 file, top-level user entries not in the new metadata are copied as top-level entries (carry loop). The file now has `"metadata"`, so `_file_metadata` ignores them. Invisible, carried forever. Fix: skip all non-group legacy entries when `previous` is < v3.
3. **0.4 rewriting a v3 file** (documented) could be detected rather than needing `force_postprocess`: a `"metadata"` entry plus a `"raw"` stored without the field means 0.4 wrote the data. `:postprocessed` could then be dropped, and 0.4's fresh top-level `"sources"` preferred over the stale `metadata[:sources]`, which `_code_changed` currently compares.
4. **Breaking for user files outside the cache:** a 0.4 dataset saved with `jldsave`/`@save` now loads as `JLD2.ReconstructedMutable` with plain JLD2 (`plain.jl`), and the typemap is internal (`_dataset_typemap`). Worth a line in the PR's breaking-change notes, or a documented way to read such files.
5. **Downstream:**
   - PDEStudio's `_select_snapshots` (src/DataHandler.jl:210, 230) builds datasets positionally without metadata. This is fine for display, and the optional argument doesn't break the constructors.
   - HyperCloud and HyperCloudCore don't use the removed reserved keys, the file entries or the positional constructors.
   - Nothing breaks downstream.

## Verdict

The core design works:
- 0.4 datasets of all kinds I tried load as the current types, with no recomputation and no writes. 0.4 can still read v3 files, and v3 reads files 0.4 rewrote.
- The Upgrade path costs no extra copies (identical allocations, at most about 10 ms more for a 115 MB Lagrangian file).
- The hash is unchanged.
- Tests pass at `-t 1` and `-t 8`, the new tests fail on the old src, and the docs build.

What needs fixing before release:
- **F1:** a legacy `"metadata"` user entry turns one file into a permanently failing task and breaks `sim_data_table` for the folder.
- **F3:** metadata entries can't be removed through the public API.

The rest are narrow edges and doc corrections.

Counts: 0 high, 2 medium (F1, F3), 6 low (F2, F4–F8), all CONFIRMED with probes in `$R/probes/`; 5 minor.
