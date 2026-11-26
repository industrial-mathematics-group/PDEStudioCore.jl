# PDEStudioCore.jl

Headless backend for running, storing and analysing PDE simulations: Eulerian
(`ESimData`) and Lagrangian (`LSimData`) datasets of any dimension, `SimulationConfig`
parameter sweeps, deterministic SHA-256 hashing with atomic JLD2 caching, conversions
between representations, and a multithreaded statistics pipeline. Must run without a
display (clusters, CI); no Makie or GUI dependencies here.

## Commands

```bash
julia --project -e 'using Pkg; Pkg.test()'                 # full suite
julia --project=test -e 'using Pkg; Pkg.instantiate()'      # once
julia -t 8 --project=test test/runtests.jl                  # same suite, faster to iterate
julia --project=docs docs/make.jl                           # docs (instantiate docs env first)
pipx run --spec aisignoff==0.20.1 aisignoff report --html docs/src/assets/aisignoff.html --with-source  # optional, before make.jl: the AI Signoff Report page (CI does it)
```

The built-in examples (`src/Examples/`, exported as `test_*`) are tested in `test/test_examples.jl`: each config
runs, and each solver shows what its docstring claims (stability limits, order, conservation). Keep them quick
(each runs in about a second) and their docstrings true: PDEStudio's quick start uses them.

## Layout

| Path | Contents |
|:-----|:---------|
| `src/Structs.jl`, `src/SimData.jl` | Types: `ParamDict`, `SimulationConfig`, `ESimData`/`LSimData`/`NoSimData`, `DomainInfo`, `StatsView` |
| `src/Config.jl`, `src/Constructors.jl` | `SimulationConfig` behaviour, `create_*` constructors |
| `src/Serialization.jl` | `val2str`/`str2val`, parameter normalisation, `calculate_hash` |
| `src/IOUtils.jl`, `src/DataManagement.jl` | The store (one file per run), save/load, atomic writes, listing, import/delete |
| `src/ConversionUtils.jl` | Eulerian ↔ Lagrangian conversion, resampling |
| `src/StatCalculation.jl` | Stat registry, `calc_stat` evaluation, references |
| `src/Simulations.jl` | Task generation, `run_all_simulations`, `run_smart_simulation` |
| `src/Examples/` | Built-in examples (`PDEStudioCore.Examples`): solvers, exact solutions, `test_*()` configs |
| `presets/` | Stat presets (`hyperbolic.jl`), loaded with `set_stat_preset!` |

## Invariants (treat changes as breaking)

- **Hash stability.** Cache file names are `calculate_hash` of the normalised parameters
  (`data/<hash>.jld2`), which depends on the encoding in `_identity` and on `val2str`/
  `_normalize_params`. Any change there renames every user's cached result. Don't change it
  unless asked; if you must, say so prominently in the PR and mention `import_sim_data`. `test/test_serialization.jl` pins the formats:
  never "fix" a failing hash test by updating the expected value without asking.
- **`str2val` never evaluates code.** It's a literal parser (CSV/config values come from
  files). Don't add `eval`, `Meta.parse` + `eval`, or `include` to it.
- **No backwards compatibility.** A version reads and writes its own file format (`_FORMAT_VERSION`); files of any
  other format aren't part of the store (not found, listed, loaded, imported or replaced: `_store_params`,
  `_file_state` → `:format`). A change of the layout or of what the statistic records mean is a new format version,
  without migration code.
- **Atomic writes.** Data is written to a temporary file and renamed into place; keep it
  that way for every new writer.
- **The store never moves or deletes data on its own.** A run is only ever written to its
  own name, after checking that the file there holds its parameters. No renaming, staging,
  duplicate cleanup or other in-place maintenance; only `delete_sim_data` deletes.
- **The store's contract** is written down in `docs/src/data.md` ("The contract"): what it
  guarantees and what it assumes (files written by PDEStudioCore, no symbolic links in the
  data folder, one writer per run, callbacks don't change parameters, floating-point data,
  imports from outside the data folder). Keep features inside it: refuse what's outside it
  instead of handling it (e.g. no interactive or parameter-changing imports beyond
  `remove_keys`). A review finding that needs one of these assumptions broken is hardening,
  not a bug; weigh it against the code it would add.
- **Parameter normalisation is frozen.** What identifies a parameter value is specified in
  `docs/src/data.md` ("What identifies a parameter value") and pinned by the corpus test in
  `test/test_store.jl`. Only data identifies a run: custom types declare their identity
  (`param_identity` / `@param_struct`), functions and undeclared structs are refused (strict).
  Values that differ only in what the rules leave out (what an identity omits, a type's module,
  Float32 vs Float64) are one value by design: refuse
  collisions (as `generate_tasks` does), don't special-case them. A change to the rules is
  a new hash format (`_HASH_FORMAT`, data brought over with `import_sim_data`), never a
  silent patch.
- **Name resolution.** Solvers, references and post-processing functions are referenced
  by name and resolved in the module set with `set_target_module!` (default `Main`;
  HyperCloud sets itself). Only names that module (or a submodule) defines itself resolve;
  imported bindings (`Base`, PDEStudioCore, other packages) are refused on purpose, because
  configuration files name these functions. Don't replace that with function objects in
  stored configs, and don't widen the lookup.
- **Stat names and presets** (`:l1error`, `:mass`, … in `presets/hyperbolic.jl`) are used
  downstream (HyperCloud, HyperCloudCore tests, PDEStudio); don't rename them.
- `data.stats[:Solution]` is always the solution itself.

## Conventions

- Requires Julia 1.12.
- Breaking releases have no deprecated aliases and no migration guide. If a change the
  user asked for is breaking, say so prominently in the PR description.
- New statistics: `register_stat!(name, kept_dims)` plus a `calc_stat` method: `calc_stat(::Val{name}, fixed, u,
  domain)` for one of the data alone (simulation layer), with `ana` before `domain` for one that uses the reference
  (reference layer); see `src/StatLayers.jl`. Statistic names are unique across the layers. Test them on a case with
  a known exact value.
- Threaded code uses Polyester `@batch` / `Threads`; results must not depend on the thread
  count (test with `-t 1` and `-t 8` when touching it).
- Tests use `set_save_path!(mktempdir())`; never write into the repo or the user's data.
- Every export needs a docstring that appears in the docs (`checkdocs = :exports`).
- Commit subjects: short and imperative, describing the behaviour change
  (e.g. `Hash enum parameters by value`).

<!-- aisignoff:begin -->
## AI signoff

This repository declares AI use with [aisignoff](https://industrial-mathematics-group.github.io/aisignoff/).
Before you commit or open a pull request, run `aisignoff guide --role dev` and follow it.
If you are reviewing a change instead, run `aisignoff guide --role review`: a reviewer only reviews and changes nothing.
<!-- aisignoff:end -->
