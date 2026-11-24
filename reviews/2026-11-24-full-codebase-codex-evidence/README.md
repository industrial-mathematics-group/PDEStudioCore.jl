# Reproducing the whole-codebase review

From the repository root, use the Julia project at the reviewed commit. All runs use temporary directories.

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project reviews/2026-11-24-full-codebase-codex-evidence/entry.jl
julia -t 2 --project reviews/2026-11-24-full-codebase-codex-evidence/check.jl
julia -t 2 --project reviews/2026-11-23-checked-import-codex-evidence/check.jl
```

- [entry.jl](entry.jl) stores a calibration with a custom JLD2 writer. It leaves reading enabled and makes serialization fail for the next save. [Standard output](entry.txt) shows that the save returned the destination and the calibration key disappeared. The script captures the warning in memory.
- [check.jl](check.jl) runs a post-processor against a single configured run while a second run is present, edits a reference parameter during import, and compares two Float16 statistics against Float64 controls. [Standard output](check.txt) gives the values before and after each operation.
- The [previous review script](../2026-11-23-checked-import-codex-evidence/check.jl) replaces a source during a later interactive prompt and exercises failure to create the destination directory. [Current output](prior.txt) confirms both behaviors.
