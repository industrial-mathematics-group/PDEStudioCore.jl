# Robustness review of declared parameter identities in PDEStudioCore.jl

| | |
|---|---|
| Reviewed | 2026-11-24. `industrial-mathematics-group/PDEStudioCore.jl` #52 at `78a30a82980c0cfac7664066b26a1491e0c09f32`, first parent `c60f98dd2941d58dca312ac37a9d0984cb5cec55`. Rechecked the earlier fix target #50 at `c45656de51caf99d21baeeae430245b775063dbd`, whose first parent was `2a1014abb8c95a31c53d12a992999cd3c7b24a46`. |
| Reviewer | GPT Sol (OpenAI), new session without the generating conversation. |
| Level | A3 for #52. Claude Opus and GPT Sol are different tier-2 models, and this review adds two independent scripts run on the reviewed code and its first parent. The #50 recheck is recorded at A2. |
| Highest finding in #52 | `critical` |

All 1,636 package tests passed. The additional checks confirmed that a simple explicit identity ignores fields it omits, can find a compatible pre-existing file, and is stable across two fresh processes with different imports. Four cases in the new identity API still break the cache contract or prevent a supported pipeline invocation.

## Findings in #52

1. **Critical. Distinct declared field names can produce the same cache key.** `src/Serialization.jl:79–82` joins unquoted identity field names and rendered values. A declaration returning `(; left = 1, right = 2)` and one returning a single field named `Symbol("left=1, right")` with value `2` produce the same stored text, `Delimiters(left=1, right=2)`. Both are valid Julia `NamedTuple` values, and the declaration selects between them from the mode of one struct. In two separate pipeline calls, the second configuration reused the first run and returned 10 instead of 20. The first parent used different hashes and returned 20. Encode field names and values with explicit boundaries, or constrain and validate field names before hashing. Add an end-to-end check with two separate configurations. [Serializer](../src/Serialization.jl#L76) · [Head](2026-11-24-pull52-identity-codex-evidence/head.txt) · [First parent](2026-11-24-pull52-identity-codex-evidence/base.txt)
2. **Major. `@param_struct` can leave out a stored field.** `src/Serialization.jl:504` enumerates public `propertynames` and calls `getproperty`. A struct exposing only `public_value` through its property interface and carrying a stored `hidden_value` hashes the same for hidden values 1 and 2. The first run produced 10. The second reused that field where its solver would return 20. The first parent has the same behavior in its generic serializer. The new macro promises that every field contributes to the declared identity. Use `fieldnames(typeof(x))` and `getfield` for the all-fields declaration. [Macro](../src/Serialization.jl#L482) · [Head output](2026-11-24-pull52-identity-codex-evidence/head.txt)
3. **Major. Ignored fields in dictionary keys can change the hash.** `src/Serialization.jl:71–75` orders dictionary keys by `string(key)` before it serializes their declared identities. I declared a key's `id` as its sole identity and swapped only the `work` fields of keys 1 and 2. The identity pairs and mapped strings stayed the same, but the rendered dictionary order flipped, producing different hashes. For dictionaries containing declared structs, the ordering survives as part of the fallback text and a lookup uses a different filename. Sort by canonical key identity and handle equal canonical keys explicitly. [Dictionary serializer](../src/Serialization.jl#L71) · [Head output](2026-11-24-pull52-identity-codex-evidence/head.txt)
4. **Major. A declaration loaded through `config.sources` can be rejected during task generation.** `src/Simulations.jl:642–643` includes source files and then generates tasks in the caller's current Julia world. `src/Serialization.jl:506–509` checks `hasmethod` in that world before the lookup through `invokelatest` can run. From a function I called the pipeline with a source file defining the identity of a pre-existing parameter type. It raised “doesn't declare what identifies it.” The method was visible in the latest world, and a latest-world retry ran the solver and produced 3. Make declaration detection and invocation use the same world, and test the normal pipeline entry point from a function with a source-defined declaration. [Pipeline](../src/Simulations.jl#L634) · [Declaration lookup](../src/Serialization.jl#L506) · [Output](2026-11-24-pull52-identity-codex-evidence/compatibility.txt)

## Outside #52

**Minor. A function filter can match a run identified by the string `"Closure"`.** `src/Serialization.jl:624–625` uses `_normalize_param` directly when matching filters and skips the validation used by `calculate_hash`. On both versions, `delete_sim_data(ParamDict(:value => sin); dry_run = true)` selected a saved run whose value is the string `"Closure"`. Use the same parameter validation before matching store filters. The reproduction uses a temporary store and a dry run. [Filter matching](../src/Serialization.jl#L624) · [Head and first-parent output](2026-11-24-pull52-identity-codex-evidence/README.md)

## Earlier findings and checks that passed

- The new contract explicitly identifies type parameters by name. The original `Matrix` pair still shares a key under that rule, and the suite verifies that a sweep containing both is refused. This review's field-name collision occurs between two distinct declared identities of one struct.
- The earlier unregister-and-restore reproduction now drops the inactive L1 and recomputes it as 6 when restored. The dry-run warning describes a planned refresh. The `∇` module identifier hashes the same before and after import. The old mixed-cache recovery and the Float64 scatter magnitude limit are documented.
- The new probes confirmed rejection of nested undeclared structs, identities returning a value other than a `NamedTuple`, and a function returned as an identity field. A separate process with the module import produced byte-identical probe output. A simple struct declared with `@param_struct` found the same file written by the first parent.

[Earlier review](2026-11-24-main-c45656d-codex.md) · [Prior-case output](2026-11-24-pull52-identity-codex-evidence/prior.txt) · [Evidence and reproduction commands](2026-11-24-pull52-identity-codex-evidence/README.md)

## Scope and commands

I read the full #52 diff and followed declared identities through task generation, lookup, storage and filtering. The independent probes focus on hashing and the public pipeline that uses it. The suite covers the numerical examples and the neighboring reference-statistics changes. Local runtime checks used Julia 1.13.4 on Linux. The downstream frontends and other platforms were outside those checks.

| Command | Result |
|---|---|
| `git diff HEAD^ HEAD --check` | No whitespace errors. |
| `uvx --from aisignoff==0.20.1 aisignoff guide --role review` and `uvx --from aisignoff==0.20.1 aisignoff lint` | History enabled. All 81 files and 10,175 lines declared. Five older merges use fallback declarations. |
| `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'` | All 1,636 tests passed. |
| `julia -t 2 --project identities.jl` | Ran on both revisions and again on head with `visible`. The two head outputs were identical under `cmp`. |
| `julia -t 2 --project compatibility.jl prepare ROOT` and `julia -t 2 --project compatibility.jl read ROOT` | Prepared a store on the first parent and read it on head with the same hash. The source-defined declaration failed inside a function and succeeded on a latest-world retry. |
| `julia -t 2 --project reviews/2026-11-24-main-c45656d-codex-evidence/edge_cases.jl` | Rechecked #50's type-name, statistics, dry-run, Unicode and Float64 scenarios. |
| `uvx --from aisignoff==0.20.1 aisignoff report --html docs/src/assets/aisignoff.html --with-source`, `julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, and `julia --project=docs docs/make.jl` | Generated the signoff page and built the docs. Documenter skipped deployment locally. |

BLOCKING
