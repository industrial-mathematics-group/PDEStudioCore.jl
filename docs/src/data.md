# Data: Creation, Storage and Conversion

## 1. Creating Datasets

[`create_sim_data`](@ref) builds Eulerian and Lagrangian datasets of any dimension. The global statistic registry is copied into the dataset, the parameters are copied, and `:Solution` is coupled to `u`.

### Eulerian (grids)

```julia
# 1D + time: u[i, n]
create_sim_data(x, u, t, params)

# 2D + time from axis vectors: u[i, j, n]
create_sim_data((x, y), u, t, params)

# static 3D field with custom axis names
create_sim_data((r, θ, φ), ρ, params; dims = (:r, :θ, :φ))

# ndgrid-style coordinate arrays (x_grid[i, j] == x[i])
create_sim_data((x_grid, y_grid), u, t, params)
```

The solution may be given as
- an array of `SVector`s (`M` components),
- an array of numbers (a scalar field, `M = 1`),
- an array of numbers with one extra trailing dimension holding the components (`u[i, j, n, c]`),
- an array of vectors.

Integer data is stored as `Float64`; `Float32` data stays `Float32`. Axes must be sorted. Beyond three spatial dimensions the default axis names are `:x1, :x2, …`; time is always the last axis (`time_dim = :t` by default).

`xmins`, `xmaxs`, `tmin` and `tmax` override the bounding box (e.g. the physical domain `[0, 1]` of a cell-centred grid). The integration measure (`domain.spacing`) is always the mean node distance of the axes, independent of these overrides.

### Lagrangian (particles)

```julia
# x_traj[n][p]::SVector{DS}, u_traj[n][p]::SVector{M} (or numbers), one entry per time step
create_sim_data(x_traj, u_traj, t, params; dims = (:x, :y))

# static particles (no time axis)
create_sim_data(positions, values, params)
```

Particle counts may differ between time steps. The bounding box defaults to the extent of all positions.

### Direct construction

The `ESimData`/`LSimData` constructors validate their input (matching axes and solution sizes, consistent dimensions, time as the last axis) and couple `:Solution` themselves, so derived datasets never need any bookkeeping:

```julia
ESimData(params, domain, axes, u)          # DS is inferred from the domain
LSimData(params, domain, t, x, u)
```

### Metadata

Information about a run that isn't data, such as iteration counts, a convergence flag or the provenance, goes into `data.metadata` (a `Dict{Symbol, Any}`), not into the statistics: it is saved and loaded with the data but never plotted.

```julia
data = create_sim_data(x, u, t, params; metadata = Dict(:iterations => 412, :converged => true))   # e.g. in a solver
data.metadata[:note] = "rerun with the fixed boundary"
save_sim_data(data; overwrite = true)
load_sim_data(params).metadata[:iterations]   # 412
```

The pipeline writes three entries itself (any value of the same name is replaced):

| Entry | Content |
| :--- | :--- |
| `:provenance` | how the data was made: versions of PDEStudioCore and Julia, host, time, number of threads, git commit of the active project (the repository its folder is in, read from `.git`; uncommitted changes are not recorded), and for pipeline runs the solver (`:solver`, `:solver_module`, `:solver_version`) and the seconds it took (`:wall_time`) |
| `:sources` | SHA-256 digests of the source files of the run (pipeline runs with `sources`) |
| `:postprocessed` | the post-processors that ran on this data (name => the digests of the source files and the package's version), so the pipeline doesn't run them again |

The metadata saved is the dataset's own: new data replaces the stored metadata (with a new provenance, without `:sources` and `:postprocessed`), and an entry you remove from `data.metadata` stays removed when you save. Writing the same data again (statistics, post-processing, `save_sim_data` of the stored data, e.g. after [`add_stat!`](@ref), or a recomputed dataset) takes the pipeline's entries of the stored metadata it doesn't have; `:postprocessed` only if the data still has the stored statistics (a recomputed dataset lacks what a post-processor added). Conversions carry the metadata of their source. Metadata is read with every dataset, so keep it small (large results belong into statistics or files of their own).

## 2. The Statistics View

`data.stats` returns a [`StatsView`](@ref): a dictionary whose `:Solution` entry is `data.u` itself.

| Operation | Effect |
| :--- | :--- |
| `data.stats[:Solution]` | returns `data.u` |
| `data.stats[:Solution] = v` / `data.u = v` | replaces the solution (size-checked) |
| `delete!(data.stats, :Solution)` | error: the solution cannot be removed |
| `data.stats[:name] = v`, `delete!(data.stats, :name)` | edit derived statistics |
| `keys`, `values`, `pairs`, `haskey`, `get`, `length` | as for a `Dict`, including `:Solution` |
| `copy(data.stats)` | plain `Dict` snapshot |

On disk, the solution is stored once (in `u`).

## 3. Storage Layout

Every run is one file, `<save path>/data/<sha256>.jld2`, named by the hash of its normalised parameters ([`calculate_hash`](@ref)), so a run is found again from its parameters alone. The hash digests a canonical encoding of the parameters in which every value carries its kind and every text its length, so distinct parameters never share an encoding (`true` and `1`, `"1"` and `1`, a matrix and a vector of the same numbers differ; hash format 4, PDEStudioCore 0.8). A lookup also checks the parameters stored in the file: a file is only ever taken for, and replaced by, the run its name stands for. A file at the name of a run that holds other parameters, or whose parameters can't be read (e.g. copied there by hand, or a symbolic link whose target is missing), is never replaced: saving that run is an error, and the pipeline reports it as failed without running it.

The store has a single rule: data is only ever written to its own name, atomically (see below). Nothing moves, renames or deletes data on its own: only [`delete_sim_data`](@ref) deletes, and only what you ask for ([`tidy_sim_data`](@ref) removes leftover temporary files). There are no duplicates of a run, so nothing has to choose between copies or clean them up.

**Data of earlier versions** (other names) isn't found: PDEStudioCore is in an early stage and keeps no compatibility with them. Recompute it, or copy runs of PDEStudioCore 0.5 to 0.7 (file format 3) into the store with [`import_sim_data`](@ref); the old files are only read. Files of PDEStudioCore 0.4 aren't read at all.

Each file contains:

| Entry | Content |
| :--- | :--- |
| `"raw"` | the native dataset |
| `"native"`, `"params"`, `"stat_keys"`, `"registry"`, `"shape"`, `"dim_keys"`, `"time_dim"` | fast metadata, read without loading the data (`"shape"` is `size(u)`, or time steps and total particle count for Lagrangian data; the axes are stored since November 2026, see [`get_sim_data_info`](@ref)) |
| `"format_version"` | the layout of the file (see below) |
| `"metadata"` | the dataset's `metadata` (stored once, here: `"raw"` holds the dataset without it), read and updated without loading the data |
| `"evaluated_stats"` | statistics already evaluated for this data |
| `"evaluated_with_reference"` | whether a reference function was available when they were last evaluated |
| `"evaluated_reference"` | which reference the values evaluated with one were evaluated with (its name, package version and the digest of the file defining it; `""` if unknown, e.g. from `calculate_all_stats!`): with another or an unknown one the pipeline evaluates them again. An evaluation without a reference, or with nothing to evaluate, keeps it |
| `"conv_L"`, `"conv_E_<n1>x<n2>…"` | cached conversions |

Other entries (e.g. written with JLD2 directly) are kept when the data is rewritten; if one of them can't be copied, the rewrite fails and the file stays as it was.

The **format version** is 3 for files written by PDEStudioCore 0.5 and later. Files of earlier layouts (0.4) count as missing: the pipeline recomputes them.


Writes are atomic: a file is written to a temporary path and renamed into place, so an interrupted run never corrupts existing data, and rewriting the data does not grow the file. This includes the bookkeeping entries of the statistics pass and cached conversions: they are written into a copy of the file that then replaces it (a changed bookkeeping entry grows the file by about its own size, a few hundred bytes to a few kB). When the data itself is rewritten, the other entries are loaded and stored again: load the packages that define the types of entries you stored yourself first, otherwise they are kept as JLD2's reconstructions (with a warning). Writers in several processes are not coordinated: if two of them rewrite the same file at once, the last rename wins. Rewriting the raw data drops stale conversion caches but keeps any other entries (including groups) you stored yourself.

Converted and reference datasets carry the parameters of the native run, so they map to the same file. They are marked as derived (`data.metadata[:derived]` is `:conversion` or `:reference`), and [`calculate_all_stats!`](@ref) never saves them: neither over the native data nor as the data of parameters that have no file yet (the next run would take the reference for the solver's result). An explicit `save_sim_data(...; overwrite = true)` of such a dataset does store it, as the native data of its parameters.

## 4. Loading and Converting

```julia
load_sim_data(params)                         # native data
load_sim_data(params, :eulerian, (100, 50))   # grid at spacetime resolution (Nx, Nt)
load_sim_data(params, :lagrangian)            # particles
enable_cache!(true)                           # store conversions in the file
```

- **Eulerian → Eulerian** ([`resample_eulerian`](@ref)): linear interpolation in space, nearest-neighbour in time (no cross-fading of snapshots); statistics are resampled along the dimensions they keep. Axes whose resolution does not change (e.g. adaptive time steps) are kept as they are.
- **Lagrangian → Eulerian** ([`convert_to_eulerian`](@ref)): inverse-distance scatter of particles and per-particle statistics; empty cells become `NaN`. Output times take the nearest recorded snapshot.
- **Eulerian → Lagrangian** ([`convert_to_lagrangian`](@ref)): grid nodes become stationary particles (sharing one position vector); fields become per-particle statistics.

The resolution `res` always lists every axis: the spatial resolutions followed by the number of time slices.

## 5. Managing Data

```julia
does_sim_data_exist(params)                         # without loading the data
get_sim_data_info(params)                           # kind, shape, axes and stored time steps, without loading the data
find_sim_data(Dict(:N => 100))                      # list the files of every run with N = 100 (any subset of the parameters)
delete_sim_data(Dict(:scheme => "upwind"); dry_run = true)   # preview, then delete
import_sim_data("old_results/data")                 # copy runs from another folder (other versions, machines) into the store
load_sim_data("a1b2c3"; key = "raw")                # by hash prefix (REPL inspection)
check_data(data)                                    # min/max/mean/NaN summary as a DataFrame
sim_data_table(Dict(:scheme => "upwind"))           # one row per run: file, size, shape, stats, solver, wall time, parameters
tidy_sim_data(dry_run = true)                       # leftovers of killed writes, and files that aren't part of the store
```

`find_sim_data` prints one line per matching run (most recently written first) with the remaining parameters and returns the paths; `delete_sim_data` deletes exactly the files it would list and refuses an empty filter. `sim_data_table` reads only the metadata of each file, so it is quick for large data folders. These three only see the store: files at their own name. Their filters compare values as the hash tells them apart: `Dict(:k => 1)` matches neither `true` nor `1.0`.

[`import_sim_data`](@ref) reads runs from a file or folder (recursively), normalises their parameters again and writes each to its name in the store; it never changes its source (also not with `overwrite = true`, also when the source is the data folder itself), and a run that is stored already is skipped, so an interrupted import is simply run again. Each source file is checked first: it must hold a dataset whose parameters, kind and shape are those stored in the file. A stored file of the same parameters that isn't a usable run (e.g. without its dataset) is replaced; a file of other parameters, a symbolic link or one of the source files is never replaced. What is installed is a copy with the SHA-256 digest the source had when it was checked: a source whose bytes change during the import (e.g. during a prompt) is reported, and its destination stays as it was. A run imported with other parameters loses its statistics (except the solution), their evaluation records and its post-processing record: the pipeline evaluates them again for the new parameters. (Saving follows links instead: `save_sim_data` writes into the file a link at the run's name points to, if that file holds the run, and keeps the link.) It also changes parameters of stored runs: `import_sim_data(joinpath(get_save_path(), "data"); remove_keys = [:obsolete])` stores every run under its parameters without `:obsolete`, and the files of the old parameters stay until you delete them.

[`tidy_sim_data`](@ref) removes temporary files of writes that never finished (older than an hour by default) and lists the files in the data folder that lookups don't use: other names (e.g. of earlier versions), parameters with another hash than the name, or parameters that can't be read. It never deletes them: import what you need, then delete them yourself.

A lookup is a single path, so files added or removed by other processes are seen at once. Parallel jobs computing the same parameters write the same file; the last rename wins.

## 6. Parameter Normalisation

Before hashing and saving, parameters are normalised: closures become `"Closure"`, custom structs become a descriptive string and other values round-trip through [`val2str`](@ref)/[`str2val`](@ref). Strings are always kept verbatim, so a parameter such as `:ic => "sin"` stays a string. [`str2val`](@ref) only parses literals (numbers, strings, symbols, tuples, vectors, `Dict`s, static arrays, arithmetic like `2π` and a range as the whole value, e.g. a sweep typed as `1:10`); it never executes code. Types come from an allowlist (numbers, text, the containers [`val2str`](@ref) writes and StaticArrays), and what a value may build is bounded (elements, digits, the size of types including static arrays, nesting), so a file cannot run code, and these limits bound what the parser computes and compiles for a text; anything else is kept as a string. Inspect the stored form with [`print_clean_params`](@ref).
