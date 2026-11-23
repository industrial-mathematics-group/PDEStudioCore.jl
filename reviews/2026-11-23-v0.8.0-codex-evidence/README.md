# Reproducing the v0.8.0 review

The script creates disposable JLD2 files. It uses the importer's supported interactive parameter prompt to model an atomic replacement by another producer while the import waits. The parameter of the second input stays unchanged. The allocation case warms the import in each version before measuring Julia allocations on a one-million-node dataset excluded by a parameter filter.

From the review checkout, run these commands in Bash with Julia 1.13.4 on Linux.

```bash
e="$PWD/reviews/2026-11-23-v0.8.0-codex-evidence"
old_case="$PWD/reviews/2026-11-23-one-file-store-codex-evidence/check.jl"
t=$(mktemp -d)
git worktree add --detach "$t/previous" 157a908eec396e46fa7a220e4e88097ae48b56e3
git worktree add --detach "$t/v071" 8fdead725ef6898db6f199668d52af36f6272b72
julia --project -e 'using Pkg; Pkg.instantiate()'
for env in previous v071; do
    julia --project="$t/$env" -e 'using Pkg; Pkg.instantiate()'
done
julia -t 2 --project "$e/check.jl"
julia -t 2 --project="$t/previous" "$e/check.jl"
julia -t 2 --project="$t/v071" "$old_case" seed "$t/seed"
julia -t 2 --project "$old_case" import "$t/seed"
```

[check.jl](check.jl) produces the [v0.8.0 output](current.txt) and [comparison output](previous.txt). [Legacy output](legacy.txt) records the two commands that write the real 0.7.1 sample and import it with 0.8.0. Allocation counts are Julia heap allocations for the invocation, rather than peak process memory.
