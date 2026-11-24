# Reproducing the main-branch review

`check.jl` creates all its simulation files in a temporary directory. It exercises reference-dependent statistics across a reference edit and restoration, parameter hashing before and after an import, and the scatter of one Float32 particle to its own grid node. It prints the results so that the same script can run at both revisions.

From the package checkout, keep a copy of `check.jl` outside the checkout and run these commands at each revision.

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
julia -t 2 --project /path/to/check.jl
```

The captured runs used Julia 1.13.4 on Linux and shared the manifest resolved at the reviewed head.

- [head.txt](head.txt) is from `8b86a74a6ac521d3a02a929b3e8c5a0912d1378d`. After A is restored the task reports `cached` and retains L2 = √18.
- [base.txt](base.txt) is from `91a629612f66acbbbc3790b6aa853947d3661e5f`. After A is restored the task reports `ran` and produces L2 = √2.
- Both runs print different hashes for the same type before and after importing its unqualified name, and both return `Inf` for the single particle with finite state.
