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

Data lives in `<save path>/data/<timestamp>_<sha256>.jld2`. The hash is computed from the normalised parameters ([`calculate_hash`](@ref)), so a run is found again from its parameters alone. Each file contains:

| Entry | Content |
| :--- | :--- |
| `"raw"` | the native dataset |
| `"native"`, `"params"`, `"stat_keys"`, `"registry"`, `"shape"`, `"dim_keys"`, `"time_dim"` | fast metadata, read without loading the data (`"shape"` is `size(u)`, or time steps and total particle count for Lagrangian data; the axes are stored since November 2026, see [`get_sim_data_info`](@ref)) |
| `"format_version"` | the layout of the file (see below) |
| `"provenance"` | how the data was made: versions of PDEStudioCore and Julia, host, time, number of threads, git commit of the active project (the repository its folder is in, read from `.git`; uncommitted changes are not recorded), and for pipeline runs the solver (name, module, package version) and the seconds it took |
| `"postprocessed"` | the post-processors that ran on this data (name => the digests of the source files and the package's version), so the pipeline doesn't run them again |
| `"evaluated_stats"` | statistics already evaluated for this data |
| `"evaluated_with_reference"` | whether a reference function was available when they were evaluated |
| `"sources"` | SHA-256 digests of the source files (pipeline runs with `sources`) |
| `"conv_L"`, `"conv_E_<n1>x<n2>…"` | cached conversions |

The entries above, except `"evaluated_with_reference"` and `"sources"`, are reserved: `save_sim_data(...; metadata)` refuses them (and any other `conv_*` name). Other metadata entries are stored as they are and kept when the data is rewritten. `"provenance"` and `"postprocessed"` describe how the data was made: they are kept when the same data is written again (statistics, post-processing, [`rehash_sim_data`](@ref), `save_sim_data` of the stored data, e.g. after [`add_stat!`](@ref); the post-processing record only if the data still has the stored statistics) and replaced when new data is saved for the parameters.

The **format version** is 2 for files written by this version. Files of PDEStudioCore 0.4 (version 1: no version entry and no axes) are read as they are; [`upgrade_sim_data`](@ref) adds the entries they lack without rewriting the data. Files of earlier versions are upgraded by the pipeline when it finds them, or recomputed if their data doesn't load.

**Data folders shared with PDEStudioCore 0.4:** an older version that rewrites a file (e.g. `force_overwrite`) keeps the `"provenance"` and `"postprocessed"` entries of the data it replaced, so this version would take its new data as post-processed already. After such runs, use `run_all_simulations(config; force_postprocess = true)` once.

Writes are atomic: a file is written to a temporary path and renamed into place, so an interrupted run never corrupts existing data, and rewriting the data does not grow the file. This includes the bookkeeping entries of the statistics pass and cached conversions: they are written into a copy of the file that then replaces it (a changed bookkeeping entry grows the file by about its own size, a few hundred bytes to a few kB). When the data itself is rewritten, the other entries are loaded and stored again: load the packages that define the types of entries you stored yourself first, otherwise they are kept as JLD2's reconstructions (with a warning). Writers in several processes are not coordinated: if two of them rewrite the same file at once, the last rename wins. Rewriting the raw data drops stale conversion caches but keeps any other entries (including groups) you stored yourself.

Converted and reference datasets carry the parameters of the native run, so they map to the same file. [`calculate_all_stats!`](@ref) detects this (by representation, shape and the solution itself) and does not save them over the native data; an explicit `save_sim_data(...; overwrite = true)` of such a dataset does replace it.

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
rehash_sim_data(joinpath(get_save_path(), "data"); remove_keys = [:obsolete])
load_sim_data("a1b2c3"; key = "raw")                # by hash prefix (REPL inspection)
check_data(data)                                    # min/max/mean/NaN summary as a DataFrame
sim_data_table(Dict(:scheme => "upwind"))           # one row per run: file, size, shape, stats, solver, wall time, parameters
tidy_sim_data(dry_run = true)                       # older duplicates of a run and leftovers of killed writes
upgrade_sim_data()                                  # bring files of earlier versions to the current format
```

`find_sim_data` prints one line per matching file (newest first) with the remaining parameters and returns the paths; `delete_sim_data` deletes exactly the files it would list and refuses an empty filter. `rehash_sim_data` writes the renamed file before removing the old one. `sim_data_table` reads only the metadata of each file, so it is quick for large data folders. A run stored more than once (e.g. by parallel jobs computing the same parameters) is always looked up as its newest file; `tidy_sim_data` removes the older ones and temporary files of writes that never finished.

Lookups list the data directory once per change rather than on every call (an index that is rebuilt when the directory changes), so they stay fast with thousands of files. Files added or removed by other processes are seen. (On file systems with coarse or cached directory times, such as FAT or NFS, a newer duplicate of a stored run that another process wrote can be found only after the directory changes again; until then the older file of the same parameters is used.)

## 6. Parameter Normalisation

Before hashing and saving, parameters are normalised: closures become `"Closure"`, custom structs become a descriptive string and other values round-trip through [`val2str`](@ref)/[`str2val`](@ref). Strings are always kept verbatim, so a parameter such as `:ic => "sin"` stays a string. [`str2val`](@ref) only parses literals (numbers, strings, symbols, tuples, vectors, `Dict`s, static arrays, arithmetic like `2π` and a range as the whole value, e.g. a sweep typed as `1:10`); it never executes code. Types come from an allowlist (numbers, text, the containers [`val2str`](@ref) writes and StaticArrays), and what a value may build is bounded (elements, digits, the size of types including static arrays, nesting), so a file cannot run code, and these limits bound what the parser computes and compiles for a text; anything else is kept as a string. Inspect the stored form with [`print_clean_params`](@ref).
