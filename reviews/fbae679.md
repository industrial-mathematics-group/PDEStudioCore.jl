# Review: PDEStudioCore.jl — fixes of reviews/356e683.md (fbae679) at fbae679

Reviewer: Claude Opus 5.5 (Anthropic), new session without the generating conversation

## Scope

- **Read:**
  - `git show fbae679`, which changes `_too_nested` and its comment in `src/Serialization.jl` and adds 8 lines to `test/test_str2val_differential.jl`
  - `reviews/356e683.md` and its probes
  - the `str2val` docstring
  - `docs/src/data.md`, which this commit leaves unchanged
  - the repo `CLAUDE.md` and `PDEStudioDev/CLAUDE.md`
- **Reran:** all bypass texts and parity probes of reviews/356e683.md. Each risky text ran in its own process under `ulimit -v 6000000` and `timeout 120`, and I counted "stack overflow" in stderr.
- **Attacked the `:`/`:(` exemption:**
  - 16 assignment-class operators × 21 placements (`:op`, `: op`, `(:) op`, `x :op`, `1:op`, `x ? y :op`, `:(op …)`, `:(op) op`, comments and newlines between the tokens, …) × 3 separators × 6 bracket contexts
  - 38 keywords × 8 colon placements × 4 separators × 4 contexts
  - `@` after `:` in 8 placements × 3 separators × 4 contexts
  - unmatched closers at the top level
  - chains in the first element
  - `:~` chains
- **Hash stability:**
  - `probe_stored_params.jl` over `/workspace/julia/Simulations/data`, read-only
  - the parity sets of the rounds 29a9afa, a1f8627, 76c67a1, 87c48e2 and 356e683 against `test/reference_str2val.jl`
- **New tests against 356e683:** run in a temporary `git worktree add --detach … 356e683`, one process per test statement. The worktree has been removed, and `$R/repo` is clean at fbae679.
- **Not run on Julia 1.12:** only 1.13.3 is installed.

`R = /home/agent/.claude/jobs/d2d299f1/tmp/review-psc1f`. All probes and outputs are in `$R/probes/`. **`probes/lit/` through `lit6/` (about 54 MB of generated literals) and `probes/filterdemo/` are not to be committed.** `run.sh`, `one.jl`, `one_task.jl`, `gen_lit*.jl` and the parity scripts are adapted from earlier rounds; `run.sh` now takes `PROJ=` to choose the environment.

One slip on my side: I briefly ran `Pkg.develop` against `$R/repo/test` by mistake, pointing it at the 356e683 worktree. I reverted `test/Project.toml` with `git checkout` and re-developed the Manifest to `..`. I then reran everything that might have run against the wrong code during that window.

## Tests run

**Full suite** (`flock /tmp/julia-suite.lock timeout 60m julia -t 8 --project=test test/runtests.jl`): **1130 / 1130 passed** in 57.6 s, with no "stack overflow" in the log (`probes/fullsuite.log`).

| Probe | What | Result |
|:--|:--|:--|
| `check_all.jl` → `check_all.out` | `_too_nested` on every literal in `lit/` to `lit6/` | All 23 old bypass texts and every `sep_*` text of reviews/356e683.md are rejected |
| `run_all.out` (`lit/`, `lit2/`) | The bypass texts of 356e683 (Finding 1: `lv(8/16/31, …)` for `'`, `[1]`, `(1)`, `-1`, `::T`, `where`, `|>`, with `;`, `[ ]`, `{ }`, `f( ; )`, `T{ }`, `Dict( )` and a trailing `,`), the a1f8627 texts, the thresholds at 2–6 levels, mismatched closers, `;` parameters | **0 overflows in all 98 processes.** Rejected texts return a String in 0.0 s. `semi_*`: no overflow, ≤ 0.5 s |
| `lit3/first_*`, `sep_tuple_adj2_*`, `sep_tuple_tilde_*` | Chain in the first element, several trailing elements, `:~` chains (8/16/31 levels) | Rejected, no overflow |
| `explore_colon.jl` / `.out` | Assignment operators after `:`/`:(` in every placement (see Scope) | **Nothing nests through `,` or newlines.** `(:~\n:~\n…)` builds depth ≈ n/4, but the chain budget bounds it. The only other deep cases are the known nested `parameters` (`;` inside `f(`/`T{`) |
| `explore_kw.jl` / `.out`, `lit3/kw_*` → `run_all.out` | Keywords after a `:` that is no quote | **`x : return 1, …`, `1:local x, …`, `x : global x, …`, `x ? y : return 1, …` and unclosed `x : begin 1; …` (also `let`, `if`, `for`, `function`, `try`, `quote`) pass `_too_nested` and overflow** (Finding 2) |
| `explore_at.jl` / `.out`, `gen_lit4.jl`, `gen_lit6.jl` → `run_lit456.out` | `@` after `:` | **`":@a 1, "^2000 * "1"` (14 KB) passes and overflows; 1000 repetitions do not.** It is rejected at 356e683 (Finding 1) |
| `run_at356e683.out` | Finding 1–2 texts at 356e683 | `kw_*`: same overflow (pre-existing); `at_*`: rejected, no overflow (regression of fbae679) |
| `one_task.jl` | Finding 1–2 texts inside `Threads.@spawn` | StackOverflowError there too |
| stderr of `at_sym_2000`, `kw_begin_semi_2000` | Where it overflows | In the JuliaSyntax **parser** (`parse_comma` "repeated 1409 times"; `parse_Nary`/`parse_block_inner` 1720 times), then a String after ≈ 1.2 s, with "program state may be corrupted" |
| `lit5/top_close_*` | Unmatched top-level `)`/`]` that reset the chain, 1 MB | Not rejected, no overflow; a String in 0.07 s |
| `probe_stored_params.jl` / `.out` | All cached datasets, read-only | **4340 files, 149,850 values: 0 parse differences, 0 hash-text differences**, 82 kinds, 0 unreadable files |
| `parity_29a9afa` / `parity_a1f8627` / `parity_356e683_prev` | 95 / 126 / 126 values | 0 parse differences, 0 hash-text differences |
| `parity_76c67a1_nest`, `parity_87c48e2` | Nesting set; 193 literals | Only the known intended differences (33-deep values; `Colon`, `BitVector`, …); 0 hash-text differences |
| `parity_356e683_new` | The 77 values of reviews/356e683.md | **7 parse differences (was 36), 0 hash-text differences.** Left: `:.=`, `:.+=`, `:.~`, the 3 containers of all operators and `nestdict(30)` (pre-existing) |
| `probe_filter.jl` | A dataset with `:op => :~` saved and found at fbae679 | Stored as `:~` (a Symbol, as at a1f8627). `find_sim_data(Dict(:op => :~))` finds 1 file |
| `newtest_line.jl` → `probe_newtests.out` | The 4 new test statements at fbae679 and at 356e683 | fbae679: 4 / 4 pass. 356e683: 3 attack lines fail; the `nestfirst` guard passes, as a guard should |
| `patched.jl` + `patched_*.out` | Candidate fix for Findings 1–2 (below) on every literal, the explore probes, the 6 parity sets and the serialization, round-trip and differential test files | Rejects every overflowing text. The output of all 6 parity sets is identical to the unpatched run. The test subset passes 768 / 768 |

## Findings

### 1. Medium — CONFIRMED — `@` after `:` is exempted, so macro calls nest through commas again (14 KB overflow)

- **Where:** `_too_nested`, `src/Serialization.jl:305`, `elseif ((… is_keyword …) || k == _JS.K"@" || _JS.is_prec_assignment(k)) && !quoted`.
- **What goes wrong:**
  - At 356e683, `k == K"@"` was refused unconditionally. The commit moved it under `!quoted`, so an `@` right after any `:` is let through.
  - `:@a 1` parses as a quoted macro call whose arguments take the comma list. That brings back reviews/a1f8627.md Finding 2 for macros: `:@a 1, :@a 1, …` gives `@a((1, :(@a((1, …)))))`, about 3 levels per repetition.
  - The exemption is not needed: `val2str` writes `@` Symbols as `Symbol("@a")` (`parity_356e683_new.out` rows 31–33).
- **Evidence (`run_lit456.out`, `run_at356e683.out`):**
  - `":@a 1, "^2000 * "1"` (14 KB), `"1:@a 1, "^n`, `"x ? y : @a 1, "^n` and `"[" * ":@a 1, "^n * "1]"` for n = 10^4 and 10^5 all pass `_too_nested`.
  - Each logs StackOverflowError plus "program state may be corrupted" in `parse_comma` (repeated 1409 times) and returns a String after about 1.2 s. It overflows inside `Threads.@spawn` too.
  - At 356e683 the same texts are rejected at once.
- **Fix:** keep `k == _JS.K"@" && return true` outside the exemption (part of the patch under Finding 2).
- **Test:** `@test T(":@a 1, "^2000 * "1") && T("1:@a 1, "^2000 * "1")`.

### 2. Medium — CONFIRMED (pre-existing since a1f8627) — The exemption also applies to a `:` that is a range or ternary operator; `return`/`local`/`global` and unclosed blocks after it overflow the parser

- **Where:** `src/Serialization.jl:288`, `quoted = previous == _JS.K":" || …`. `previous` skips whitespace, and nothing checks whether that `:` is a quote. At a1f8627 and 356e683 the condition was `previous != K":"` for keywords, with the same effect.
- **What goes wrong:**
  - The comment says keywords and assignments are let through only "in Symbols such as `:begin`, `:~` or `:(=)`". In fact any keyword after a binary `:` passes, with or without whitespace: `x : return …`, `1:local …`, `x ? y : begin …`.
  - `return`/`local`/`global` take the comma list, so `x : return 1, x : return 1, …` nests about 3 levels per element.
  - Blocks after `:` that are never closed (`x : begin 1; x : begin 1; …`, also `let`, `if`, `for`, `function`, `try`, `quote`) make the recursive-descent parser recurse once per `;`. It recurses before it reports the missing `end`.
- **Evidence:**
  - `explore_kw.out` lists 66 deep cases. `run_all.out`, `run_lit456.out` and `run_at356e683.out` show the overflows; the thresholds lie between 1000 and 2000 repetitions:

    | Text | Size | Result |
    |:--|:--|:--|
    | `"x : return 1, "^2000 * "1"` | 28 KB | overflow; 1000 repetitions: none |
    | `"x : begin 1; "^2000 * "1"` | 26 KB | overflow (`parse_Nary`/`parse_block_inner` repeated 1720 times); 1000: none |
    | `kw_*` in `lit3`: `local`, `global`, `1:return`, `x ? y : return`, inside `(…)` and `[…]`, the 7 block keywords with `;` | 70 KB – 1.8 MB | overflow in all 28 processes |

  - Each case logs StackOverflowError plus "program state may be corrupted" and returns a String after 1.3–1.6 s. The same happens at 356e683.
- **Fix:** let a keyword or assignment through only after a `:` in prefix position, with no whitespace in between. Prefix position means at the start, after `(`, `[`, `{`, `,`, `;` or `=>`. Track the last three non-whitespace tokens and whether whitespace followed them; never exempt `@`. `probes/patched.jl` implements this:
  ```julia
  quoted = (p1 == K":" && !ws1 && prefix(p2)) || (p1 == K"(" && p2 == K":" && !ws1 && !ws2 && prefix(p3))
  elseif k == K"@" || (((is_keyword(k) && k != K"var") || is_prec_assignment(k)) && !quoted)
  ```
  - It rejects every Finding 1–2 text.
  - `patched_explore_kw.out` finds 0 deep cases, and `patched_explore_at.out` finds none either.
  - It changes no output of the 6 parity sets, and the serialization, round-trip and differential tests pass 768 / 768.
  - `:~` and `:(=)` stay Symbols.
- **Test:**
  ```julia
  @test T("x : return 1, "^2000 * "1") && T("1:local x, "^2000 * "1") && T("x : begin 1; "^2000 * "1")
  @test !T("[:begin, :end, :~, :(=)]") && !T(val2str(Dict(:~ => 1)))
  ```

### 3. Low — CONFIRMED — Dotted operator Symbols still become Strings (Finding 2 of 356e683, remainder)

- **Where:** the same exemption. `:.=`, `:.+=` and `:.~` lex as `:` `.` `op`, so the assignment token follows `.`, not `:`.
- **What goes wrong:**
  - `str2val(val2str(Symbol(".=")))` is `":.="` (a String), while the reference parser reads a Symbol.
  - The same holds for containers that hold one of them (`parity_356e683_new.out` rows 18–20 and 38–40).
  - The hash text is unchanged, and no cached dataset holds such a value. Only `find_sim_data`/`delete_sim_data` filters on files written before 356e683 would miss them.
- **Fix:** also exempt `prefix(p3), p2 == K":", p1 == K"."` without whitespace, or name the limitation in the comment and docstring.
- **Test:** `@test str2val(val2str(Symbol(".="))) === Symbol(".=")` (or a documented exception in the differential test).

## Per-item status of reviews/356e683.md

| Item | Status | Evidence |
|:--|:--|:--|
| 1. A separator inside a closed group drops its chain from the carry | **FIXED.** All `sep_*` texts (8/16/31 levels, every separator and bracket form) and the thresholds are rejected with no overflow. Chains in the first element and several trailing elements are rejected too | `check_all.out`, `run_all.out` |
| 2. Operator Symbols became Strings | **Mostly FIXED:** 36 → 7 parse differences; the filter matches again. Dotted forms remain (Finding 3). **The fix exempts too much:** `@` after `:` (Finding 1, a regression); keywords after a non-quote `:` (Finding 2, pre-existing) | `parity_356e683_new.out`, `probe_filter.jl`, `run_lit456.out` |

Minor issues of that review:
- **Comment line length (174 characters):** fixed. No line in the new code is over 120.
- **Commit message overclaims:** the new message has a similar one. "Assignment operators after `:` or `:(` are Symbols" does not hold for a range or ternary `:`, and `@` is exempted silently.
- **Docstring "assignments":** unchanged. It still doesn't mention the Symbol exemption.
- **`nestdict(30)` is a String:** unchanged, pre-existing, and the hash text is equal.
- **Invalid UTF-8:** unchanged. `_too_nested` throws `InvalidCharError`, and `str2val` returns the String. Harmless.
- **`docs/src/data.md` overclaim:** unchanged. It still says the limits bound what the parser computes, which Findings 1–2 contradict.

## Test coverage

- The 3 new attack lines fail at 356e683 and pass at fbae679. The `nestfirst` guard passes at both, as intended.
- Not covered:
  - `@` after `:` (Finding 1)
  - keywords after a range or ternary `:` (Finding 2)
  - dotted operator Symbols (Finding 3)
  - the whitespace case: `: begin` is let through, `:begin` is the only form `val2str` writes

## Minor issues

- **The comment at `src/Serialization.jl:273-275` describes the intent, not the code.** It says the exemption covers "Symbols such as `:begin`, `:~` or `:(=)`", but the code exempts every token after any `:` (also after whitespace) and also `@`.
- **`const _MAX_TERMS` comment (`:110`) is stale:** it still says "tokens between two separators of the text". The budget is path-wide with a longest-element carry, as `_too_nested` documents.
- **Unmatched top-level closers reset the chain** (`isempty(outer) → terms = longest = 0`). 1 MB texts such as `("1^"^500 * "1)")^1000` pass `_too_nested`, but the parser stops at the first `)` and returns in 0.07 s (`lit5/`). Harmless; a comment would help.

## Verdict

The commit fixes Finding 1 of reviews/356e683.md completely. Every separator-reset text at 8, 16 and 31 levels, and the chains in the first element, are rejected at once without an overflow. It also fixes most of Finding 2: 36 → 7 parse differences, and filters by `:~` match again.

Hash stability holds:
- 4340 datasets, 149,850 values: 0 parse and 0 hash-text differences
- 6 parity sets: 0 hash-text differences

`str2val` still evaluates no code. The suite passes 1130 / 1130, and the new tests separate 356e683 from fbae679.

Still open:
- **Finding 1 (new, regression):** moving `@` under the `:` exemption lets `":@a 1, "^2000` (14 KB) overflow the JuliaSyntax parser again.
- **Finding 2 (pre-existing since a1f8627):** the exemption doesn't check that the `:` is a quote. `x : return 1, …` (28 KB) and unclosed `x : begin 1; …` (26 KB) overflow.
- **Shared fix for both:** a prefix-position, no-whitespace check, with `@` never exempted (`probes/patched.jl`). It closes both without changing any parity result.
- **Finding 3:** dotted operator Symbols are still Strings.

Findings: 0 high, 2 medium (1, 2), 1 low (3).

Per item of reviews/356e683.md:
- 1: fixed
- 2: mostly fixed (Finding 3 remains; the exemption is too broad, Findings 1–2)
- minor items: 1 fixed, 5 unchanged (only the docs overclaim matters)

The probes are in `reviews/fbae679/`; `probes/lit/` to `lit6/` (about 54 MB of generated literals) and `probes/filterdemo/` are not committed.
