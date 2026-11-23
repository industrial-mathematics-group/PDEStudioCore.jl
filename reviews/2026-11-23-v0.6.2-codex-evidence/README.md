# Reproducing the v0.6.2 review

Run from the PDEStudioCore.jl repository root with the reviewed source at `d1a8840f0fb11042085a61b600dcd61ae68c8dc7` and this review folder present.

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
julia -t 2 --project reviews/2026-11-23-v0.6.2-codex-evidence/check.jl
```

[check.jl](check.jl) runs the reduced README heat example, followed by the cases named in the [report](../2026-11-23-v0.6.2-codex.md). It prints the observed behavior and creates disposable data directories with `mktempdir()`. The unreadable-file case truncates only its own newly created temporary result. [output.txt](output.txt) is the standard output from Linux and Julia 1.13.4. Progress bars may also appear on standard error.
