# Review: PDEStudioCore.jl — fixes of reviews/fbae679.md (583decb) at 583decb

Reviewer: Claude Opus 5.5 (Anthropic), new session without the generating conversation

## Scope

- **Read:**
  - `git show 583decb`, which changes `_too_nested` and its comment and the `_MAX_TERMS` comment in `src/Serialization.jl`, and adds 5 lines to `test/test_str2val_differential.jl`
  - `reviews/fbae679.md` and its probes
  - `val2str`, the `str2val` docstring and `docs/src/data.md`
  - the repo `CLAUDE.md` and `PDEStudioDev/CLAUDE.md`
- **Reran the fbae679 work:** all overflow texts (`lit/` to `lit6/`, 174 files), the explore probes, the 6 parity sets, the filter probe and the stored-params probe. Each risky text ran in its own process under `ulimit -v 6000000` and `timeout 120`, and I counted "stack overflow" in stderr.
- **Attacked the new quoting rule** with two grids (below), a ternary probe and a `:.`-keyword probe.
- **New tests against fbae679's code:** a temporary `git worktree add --detach … 583decb` with `git checkout fbae679 -- src/Serialization.jl`. The worktree has been removed. `$R/repo` is clean at 583decb, and I did not run `Pkg.develop` anywhere.
- **Not run on Julia 1.12:** only 1.13.3 is installed.

`R = /home/agent/.claude/jobs/d2d299f1/tmp/review-psc1g`. All probes and outputs are in `$R/probes/`.

- **Not to be committed:** `probes/lit/` to `lit6/` (about 54 MB of generated literals, from `gen_lit*.jl`).
- **Adapted from reviews/fbae679:** `run.sh` (path fixed), `one.jl`, `check_all.jl`, `explore_*.jl`, the parity scripts, `probe_stored_params.jl` and `newtest_line.jl`.
- **New in this round:** `attack_quote.jl`, `attack_quote2.jl`, `attack_stack.jl`, `attack_stack_sanity.jl`, `stackcal.jl`, `symbols_parity.jl`, `ternary_colon.jl`, `dot_kw.jl` and `probe_filter2.jl`.

## Tests run

**Full suite** (`flock /tmp/julia-suite.lock timeout 60m julia -t 8 --project=test test/runtests.jl`): **1134 / 1134 passed** in 58.2 s, with no "stack overflow" in the log (`probes/fullsuite.log`).

**Detector for parser recursion.** A deep parse doesn't always show up in the depth of the result: unclosed blocks recurse and then return a shallow `Expr(:error)`. So `attack_stack.jl` runs `JuliaSyntax.parse!` (no flisp fallback) in a `Task` with a 1 MB stack. That is a quarter or less of a normal stack, and at 2000 repetitions it amplifies any per-repetition recursion. `stackcal.jl` calibrates it:
- It catches `x : begin 1; ` and `x : return 1, ` from 100 / 200 repetitions on (256 KB stack).
- It stays silent on the known flat cases (`f(1; …)`, `Dict(1; …)` up to 10^5, 32 nested brackets).

| Probe | What | Result |
|:--|:--|:--|
| `check_all.jl` → `check_all.out` | `_too_nested` on all 174 literals of `lit/` to `lit6/` | All fbae679 Finding 1–2 texts are rejected now: 28 `kw_*`, 16 `at_*`, `lit6` thresholds 300–5000, `sym_tilde`/`sym_tern`. The 11 not rejected are the known harmless `semi_*`, `sym_colon_tilde`, `sym_quote_assign` and `top_close_*` |
| `run_all.out`, `run_notrejected.out` | Each of the 174 literals in its own process | **0 overflows, all exit 0.** Rejected texts return a String in 0.0 s. `semi_dict_1e6`: String in 0.5 s. `sym_quote_assign_1e5`: a Tuple in 0.5 s |
| `explore_kw.out` | Keywords × 8 colon placements × separators × contexts | **0 deep and not rejected** (fbae679: 66) |
| `explore_at.out` | `@` after `:` in 8 placements | Every text rejected (`T = true`) |
| `explore_colon.out` | Assignment operators after `:` / `:(` | 66 cases, all the known nested `parameters` (`;` inside `f(` / `T{`); fbae679 had 95. The 8 more than the patch had are the now-accepted `:.=` / `:.~` in that same family |
| `attack_quote.jl` / `attack_quote2.jl` | 64 payloads (35 keywords, 22 assignment operators, 6 dotted ones, `@a`) × 27–29 colon forms (`:`, `:(`, `:.`, `:(.`, `::`, `:::`, `:(:`, `: :`, `:\n`, `:#=c=#`, `=>:`, `x => :`, `(:`, …) × 6 arguments × 9 separators × 11 contexts; about 1.1 M texts; Expr depth at 50 and 100 repetitions | 233,530 pass `_too_nested`. Only two kinds grow in depth: the known `;`-parameters family (in `f(`, `T{`, `Dict(`, `(1, `; it doesn't depend on the payload), and 122 space-separated `[1 =>:kw =>:kw …]` chains, all rejected by the chain budget at 2000. Nothing is slow (> 0.2 s) |
| `attack_stack.jl` → `attack_stack.out` | Extended grid (9 arguments, 10 separators, 14 contexts including unclosed `(` / `[` and `"$(…)"`) at **n = 2000**; parser recursion in a 1 MB Task | **2,338,560 texts, 396,732 pass `_too_nested`, 0 overflow** |
| `attack_stack_sanity.jl` | The detector with payloads `@a`/`return`/`begin`/`local` after `:`, `1:`, `x : `, `x ? y : ` | **fbae679 code: ≥ 6791 overflows**; the process then hung in corrupted state and I killed it. **583decb: 90,720 texts, 0 overflows** |
| `ternary_colon.out` | A quote-position `:` (after `,`, `;`, `=>`, `(`) inside an open ternary, 12 units × 4 separators × 4 contexts at 2000 | Some pass `_too_nested`; the parser stops with an error at the first unit. 0 overflows |
| `dot_kw.out` | `:.` followed by a keyword (`:.begin`, `:.return`, `:.let`) | Passes `_too_nested`. The parser stops at the first keyword ("Expected `]`" / "extra tokens"); 0 overflows at 2000 |
| `symbols_parity.jl` / `.out` | 1469 Symbols (every JuliaSyntax kind name and its dotted form, plus edge cases) × 9 containers (bare, Vector, Tuple, Dict key/value, `Val`, `Val` of a tuple, …): `str2val(val2str(v))` against `OldStr2Val` | **13,221 values: 0 parse differences, 0 hash-text differences, 0 false rejections.** fbae679: 45 differences (`:.=`, `:.~`, `:.≔`, `:.⩴`, `:.≕`) |
| `probe_stored_params.out` | All cached datasets under `/workspace/julia/Simulations/data`, read-only | **4340 files, 149,850 values, 0 unreadable files, 0 parse differences, 0 hash-text differences**, 82 kinds |
| `parity_29a9afa` / `parity_a1f8627` / `parity_356e683_prev` / `parity_76c67a1_nest` / `parity_87c48e2` | 95 / 126 / 126 / 31 / 193 values against the reference | Output byte-identical to the fbae679 round: 0 parse differences in the first three, only the known intended differences in the last two, 0 hash-text differences |
| `parity_356e683_new` | 77 values | **1 parse difference (fbae679: 7)**, the pre-existing `nestdict(30)` (String); 0 hash-text differences |
| `probe_filter2.jl` / `.out` | Save a dataset with `:op => :~` / `:.=` / `:.~` (temporary directory), then find it | Stored as a Symbol each time. `does_sim_data_exist` is true and `find_sim_data(:op => op)` finds 1 file |
| `newtest_line.jl` → `probe_newtests.out` | The 4 new test statements, one process each, at 583decb and with fbae679's `Serialization.jl` | 583decb: 4 / 4 pass. fbae679: the 3 attack and dotted lines **fail**, and the `!T(...)` guard passes (as a guard should) |

## Findings

### 1. Low — CONFIRMED — The `:(` and `:.` branches exempt more than "Symbols only"

- **Where:**
  - `src/Serialization.jl:296-297`, the second clause of `quoted`
  - the comment at `:273-276` ("Keywords and assignment operators are let through in Symbols only …")
- **What goes wrong:**
  - The second clause exempts any keyword after `:(` and after `:.`. Some of these texts are not Symbols:
    - `:(return 1, 2)` is a quote expression
    - `:(begin 1; …` is an unclosed quoted block
    - `:.begin` and `:.return` are the Symbol `:.` followed by a keyword
  - The comment and commit message describe a narrower rule.
- **Evidence:**
  - `_too_nested(":.begin") == false` and `_too_nested(":(return 1, 2)") == false`.
  - This is harmless in practice:
    - `:(` costs a bracket, so `_MAX_DEPTH = 32` bounds it.
    - `:.` followed by a keyword is a parse error at the keyword.
    - `dot_kw.out` shows no overflow at 2000 repetitions, and `attack_stack.out` shows none for any `:(` / `:.` form.
  - `str2val(":(return 1, 2)")` returns the String.
- **Fix:** either
  - restrict the `:.` case to assignment operators (`p1 == K"."` only when `is_prec_assignment(k)`; that is all `:.=`/`:.~` need), or
  - reword the comment: "after `:(` (any token, bounded by the bracket limit) and `:.` (operators; keywords there are a parse error)".
- **Test (if restricted):** `@test T(":.begin") && !T(":.=")`.

No other findings. I found no text that passes `_too_nested` and then overflows, stalls or builds a deep `Expr` beyond the known, bounded `;`-parameters and chain-budget families. I also found no false rejection of `val2str` output.

## Per-item status of reviews/fbae679.md

| Item | Status | Evidence |
|:--|:--|:--|
| 1. `@` after `:` exempted (`:@a 1, …` overflows) | **FIXED.** `@` is refused unconditionally again | `explore_at.out` (all rejected); `lit4`/`lit6` `at_*` rejected with no overflow; sanity grid shows 0 overflows at 583decb against ≥ 6791 at fbae679 |
| 2. Exemption after a range or ternary `:` (`x : return 1, …`, unclosed `x : begin 1; …`) | **FIXED.** Only a `:` in prefix position (start, `(`, `[`, `{`, `,`, `;`, `=>`) directly before the token counts as quoting | `explore_kw.out` 0 deep (was 66); all 28 `kw_*` and the `lit6` thresholds rejected, 0 overflows; 2.3 M-text grid 0 overflows; ternary probe clean |
| 3. Dotted operator Symbols became Strings | **FIXED** | `parity_356e683_new` 7 → 1 (the remaining one is pre-existing `nestdict(30)`); `symbols_parity` 0 differences across 1469 Symbols (fbae679: 45); filter by `:.=` / `:.~` finds the file |

Minor issues of that review:
- **Comment describes intent, not code:** mostly fixed. The code now matches the comment for `:`; Finding 1 covers what's left for `:(` / `:.`.
- **Stale `_MAX_TERMS` comment:** fixed ("tokens in a chain of the text (see `_too_nested`)").
- **Unmatched top-level closers reset the chain:** now commented ("an unmatched closer starts over: the parser stops there"). Behaviour unchanged and harmless (`lit5/top_close_*`: String in 0.07 s).
- **Commit message overclaims:** fixed. The 583decb message matches the behaviour, and its "4340 cached datasets: still identical" is confirmed.
- **Docstring "assignments":** unchanged (see Minor issues).
- **`nestdict(30)` is a String:** unchanged, pre-existing, hash text equal.
- **Invalid UTF-8:** unchanged and harmless. `str2val("(1, \xff)")` returns the String.
- **`docs/src/data.md` overclaim** ("these limits bound what the parser computes"): text unchanged. With Findings 1–2 fixed, my probes found no case where it is false.

## Test coverage

- The 3 new attack/dotted lines fail with fbae679's `Serialization.jl` and pass at 583decb. The `!T([:begin, :end, :~, :(=)])` / `Dict(:~ => 1)` guard passes at both, as intended.
- Not covered by tests:
  - The whitespace and comment cases: `: begin`, `:\nbegin` and `:#=c=#begin` must be rejected. They are, but no test pins it.
  - Quote positions other than the start and `[`/`,`: `=>:begin`, `Val{:begin}()`, `(:a; :begin)`.
  - The breadth of the `:(` / `:.` exemption (Finding 1).
- Suggested additions, a cheap pin on the prefix and no-whitespace rule:
  ```julia
  @test T(": begin 1; "^2000 * "1") && T("x => :return 1, "^2000 * "1") === false
  @test !T(val2str(Val(:begin))) && !T(val2str(:a => :begin))
  ```
  - The second half of the first line documents that `=>:return 1` is let through, but only ever as a Symbol.
  - Note that `val2str(:a => :begin)` takes the struct branch and is rejected anyway, so use `Dict(:a => :begin)` instead.

## Minor issues

- **`str2val` docstring** (`src/Serialization.jl`, the docstring before `function str2val`): it still says keywords and assignments are returned as strings, without the exception that `:begin`, `:~`, `:(=)` and `:.=` are Symbols. Unchanged since fbae679.
- **Comment wording at `:275`:** "after a bracket" means an *opening* bracket. "without whitespace" refers to the gap between `:` and the token; whitespace before the `:` is allowed (`Dict(:a => :begin)`). Saying both explicitly would help.
- **Line lengths:** the changed lines are within 120 characters. The 127-character line 43 (`val2str` Dict) is pre-existing.

## Verdict

583decb fixes all three findings of reviews/fbae679.md:
- `@` is never exempted.
- Keywords and assignment operators pass only right after a quoting `:` in prefix position without whitespace.
- Dotted operator Symbols round-trip again.

Across about 3.4 M generated attack texts I found no text that passes `_too_nested` and still overflows the parser, stalls, or nests unboundedly. The detector itself overflows thousands of times on fbae679's code, so it works. All 174 earlier literals ran without an overflow.

Hash stability holds:
- 4340 datasets / 149,850 values: 0 parse and 0 hash-text differences
- 1469 operator and keyword Symbols × 9 containers: 0 parse and 0 hash-text differences
- all 6 earlier parity sets: unchanged; `parity_356e683_new` is down to the pre-existing `nestdict(30)`

`str2val` still evaluates no code. The suite passes 1134 / 1134, and the new tests separate fbae679 from 583decb.

Findings: 0 high, 0 medium, 1 low (Finding 1: the comment and the `:(`/`:.` exemption are broader than "Symbols only", but harmless).

Per item of reviews/fbae679.md: 1 fixed, 2 fixed, 3 fixed. Minor items: 4 fixed, 1 mostly fixed (now Finding 1), 3 unchanged (docstring wording, `nestdict(30)`, invalid UTF-8; all harmless). The docs claim is no longer contradicted.

The probes are in `reviews/583decb/`; `probes/lit/` to `lit6/` (about 54 MB of generated literals) are not committed.
