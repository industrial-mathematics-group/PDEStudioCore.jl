# Review: PDEStudioCore.jl — fixes of reviews/76c67a1.md (29a9afa) at 29a9afa
Reviewer: Claude Opus 5.5 (Anthropic), new session without the generating conversation

## Scope

- **Read in full:**
  - `git show 29a9afa`: `src/Serialization.jl`, `docs/src/data.md`, `test/test_str2val_differential.jl`
  - `src/Serialization.jl` at 29a9afa
  - `reviews/76c67a1.md` and its probe scripts
  - the repo `CLAUDE.md` and `PDEStudioDev/CLAUDE.md`
- **Reran:** the probe literals of `reviews/76c67a1.md` (Findings 1–3), each in its own process.
- **Attacked:**
  - `_too_nested` / `_char_literal_end`:
    - Char literals: `'\''`, `'\\'`, `'é'`, `'\U0010ffff'`, the 16-character `'\xf0\x80\x80\x80'`, `'ab'`, `''`, `'''`
    - adjoints, and `'` at the end of the text
    - triple-quoted strings, interpolation, raw strings
    - the word count: keywords, `!`, Unicode letters, `1e5`, `0x1f`, `2π`, `1.5f0`, `im`
    - `.`, `$`, non-ASCII operators
    - where the count resets (brackets, `;`)
  - `_type_size` with `L`: mismatched, free, negative and non-integer `L`; `SizedArray`; Unions; Tuples; abstract static types.
- **Hash stability:**
  - `probe_stored_params.jl` (identical to the 87c48e2 version up to the include path), read-only over `/workspace/julia/Simulations/data`
  - 95 synthetic values `val2str` writes, compared with `test/reference_str2val.jl`
- **New tests against 76c67a1's `src/`:** a scratch copy (`$R/scratch-76c67a1`), one process per test line.

`R = /home/agent/.claude/jobs/d2d299f1/tmp/review-psc1c`. Probes and outputs are in `$R/probes/`. These are not to be committed:
- `probes/lit/` (7 MB, written by `gen_lit2.jl`)
- `$R/scratch-76c67a1/`

Risky literals ran one per process under `ulimit -v 6000000` and `timeout` 120–180 s (`run.sh`, `one.jl`).

**Process note:** `$R/repo` is a git worktree, and its `.git` is a gitlink file. `cp -r` copied the gitlink, so `git checkout 76c67a1 -- src` in the copy also staged 76c67a1's `Serialization.jl` into the review worktree's index. No files in the review worktree changed (checked with `cmp` against `git show 29a9afa:…`). I restored the index with `git reset -q -- src/Serialization.jl`, and `git status` is clean again. I also deleted the copy's `.git`. For future rounds, make the scratch copy with `git show <rev>:src/… >` or `git worktree add` instead.

## Tests run

**Full suite** (`flock /tmp/julia-suite.lock timeout 60m julia -t 8 --project=test test/runtests.jl`): **1117 / 1117 passed**, 60.4 s (`probes/fullsuite.log`).

| Probe | What | Result |
|:--|:--|:--|
| `probe_review_literals.out` | Literals of reviews/76c67a1.md Findings 2–3: `('"', [[…2000…]])`, comment + 40 brackets, `1'…`×10^4, `$`×10^4, `begin`×3000, `a.a…`×10^4, `"1-\n"`×10^4, `"2^\n"`×10^4, `±`×10^5, `→`×10^5, `×`×10^5, `-`×10^5, `(`×10^5 | All → String in 0.0 s (the scanner rejects them), no stack overflow |
| `probe_static_length.out` | Finding 1 literals (78-char `Tuple{}` form, `Tuple{0}`/`Tuple{1}` forms, `Pair{…}[]`, the two-level 256 form), plus `L` = 1000, 300, −5, 1.0e6, nested 64.0 | Finding 1 literals → String in ≤ 0.05 s. Single-level `L` = 1000 parses (0.46 s). Non-integer and negative `L` are inert (≤ 0.07 s). `SMatrix{2, 2, Float64, 4}[]` and `Dict{SArray{Tuple{2}, Int, 1, 2}, Int}(SA[1, 2] => 1)` still parse |
| `probe_type_size.out` | `_type_size` of edge types | `L` is counted: `SArray{Tuple{}, Int, 0, 64}` = 69, `{…, 1024}` → String, `MArray` nested 64 × 64 → String, Union/Tuple of two 600s → String. Free `L` with `Tuple{1000}` = 1006. `SVector{1018, Float64}` parses, `{1019}` → String. `SizedArray` = 1009 (not allowlisted anyway) |
| `probe_scanner.jl` / `.out` | `_char_literal_end` against `Meta.parse`; `_too_nested` on attack texts and on val2str texts | `'\''` → end 3 of 4 (wrong). `'''` → nothing (Julia: Char). `'\xf4\x90\x80\x80'` → nothing (valid Julia Char). Nine families of bypass texts → `false` (Findings 1, 2) |
| `probe_bypass.out`, `probe_bypass_overflow.out` | Those bypass texts through `str2val`, one per process, full stderr | **`StackOverflowError` plus "program state may be corrupted" in `Meta.parse`** for `('\'','"', deep2000)`, `(''','"', deep2000)`, `(""" " """, deep2000)`, `"$(deep2000)"` (4 KB each), `begin; `×2000 (24 KB), `if true; `×2000, `(1)^`×10^4, `(a)->`×10^4, `(1)=>`×10^5, `(1)-`×10^5, `(x)'`×10^5. Each returns a String after 0.8–2.5 s |
| `probe_thresholds.out` | Shortest overflow | No overflow at: `"$(…1500…)"` (3 KB), `begin; `×1500 (18 KB), `(1)^`×5000 (20 KB) |
| `probe_after_overflow_task.out` | `"$(deep2000)"` inside `Threads.@spawn` | Overflows in the task, returns String; the process keeps working (str2val, hash) |
| `probe_char_long.out` | Invalid Chars whose `repr` has 4 `\x` escapes | No false rejection of val2str output. The hand-typed `('\xf0\x80\x80\x80','"', deep)` bypasses the scanner |
| `probe_parity.jl` / `.out` | 95 values val2str writes (Chars, quotes, `$`, `#`, Unicode identifiers, 5000-symbol lists, 3000-pair Dict, Complex/Rational/Big numbers, reshape matrices, StaticArrays, structs, enums, NamedTuple-like texts, `var"#…"` types, ranges), against the reference | **1 parse difference** (`Symbol("x" * "′"^1100)` → String). **0 hash-text differences** |
| `probe_minor.out` | Typed texts against the reference | Differences: `1 # c` and `1 #= c =#` (were `1`, now Strings) and the triple-quoted text of the old minor item. Everything else (numbers with letters, `$x`, `√2`, `begin 1 end`, `:a!`, `'''`) is the same |
| `probe_stored_params.jl` / `.out` | All cached datasets, read-only | **4340 files, 149,850 values: 0 parse differences, 0 hash-text differences, 82 (key, type) kinds, 0 unreadable files** |
| `newtest_line.jl` → `probe_newtests.out` | Each of the 10 new `@test` lines, per process, with both `src/` versions | At 29a9afa: 10 / 10 pass. At 76c67a1: 1 aborts (exit 134), 1 times out (exit 124), 6 fail, 2 pass (the `SMatrix{2, 2, Float64, 4}` guard and the Char round trip) |

## Findings

### 1. Medium — CONFIRMED — The scanner still misreads Chars and strings: nesting hidden inside them reaches `Meta.parse` and overflows its stack (4 KB)
- **Where:** `_too_nested` / `_char_literal_end`, `src/Serialization.jl:271-327`.
- **What goes wrong:** the scanner's idea of "inside a Char/string" differs from Julia's lexer in four ways. In each, a 2000-bracket nesting after the spot goes unseen:
  1. **`'\''`:** `_char_literal_end` stops at the first `'` after the backslash, which is the escaped quote. The real closing `'` then starts a new "Char". In `('\'','"', …)` that Char is `','`, and the `"` of `'"'` opens a string the scanner never closes.
  2. **`'''`** (a valid Char in Julia; `Meta.parse("'''") == '\''`) and **escapes longer than 11 characters** (`'\xf0\x80\x80\x80'`, which is how `repr` writes invalid Chars): both are read as adjoints. The same `','` / `'"'` desync follows.
  3. **Triple-quoted strings** with an odd number of inner `"` (`""" " """`): the scanner toggles on each `"` and ends up "inside a string" after the literal.
  4. **Interpolation:** `"$( … )"` is code to `Meta.parse`, but the scanner skips everything inside quotes.
- **Effect:** a stack overflow, "Warning: detected a stack overflow; program state may be corrupted", in the main thread and in tasks. The result is a String after about 1.3 s, and the process keeps working. This is the crash class the commit says it closes (old Finding 2A), reached the same way through a Char or string.
- **val2str output is not affected:** it always writes `, `, ` => `, `]` or `)` after a Char, and it escapes `$` in strings. Chars, quotes and `$` in containers round-trip, with no parse or hash difference (`probe_parity.out`).
- **Evidence:** `probes/probe_scanner.out`, `probe_bypass.out`, `probe_bypass_overflow.out`, `probe_char_long.out`, `probe_after_overflow_task.out`.

  | Text (deep = `"["^2000 * "1" * "]"^2000`) | `_too_nested` | `str2val` |
  |:--|:--|:--|
  | `('\'','"', deep)` | false | StackOverflowError, String |
  | `(''','"', deep)` | false | StackOverflowError, String |
  | `('\xf0\x80\x80\x80','"', deep)` | false | (same desync) |
  | `(""" " """, deep)` | false | StackOverflowError, String |
  | `"$(deep)"` | false | StackOverflowError, String |

- **Fix:**
  - In the escape branch, skip the escaped character before looking for the closing `'`, and allow up to 4 `\xHH` groups (16 characters).
  - Treat `'''` as a Char.
  - Refuse `"""` and an unescaped `$` inside a string. `val2str` writes neither (`repr` escapes `$` as `\$`), and the old parser already returned the same String for interpolated texts, because `Expr(:string)` is no literal.
  - More robust: drive the count from `Base.JuliaSyntax`'s tokenizer, which is iterative and lexes Chars, triple quotes and interpolation exactly.
- **Test:**
  - `@test T("('\\'','\"', " * "["^2000 * "1" * "]"^2000 * ")")`
  - the same with `'''` and with `""" " """`
  - `@test T("\"\$(" * "["^2000 * "1" * "]"^2000 * ")\"")`
  - keep `@test !T(val2str(Any['\'', '"', "\$x", "a'b"]))`

### 2. Low — CONFIRMED — The term count resets at every bracket and at `;`: bracketed chains and `;`-separated blocks still overflow `Meta.parse`
- **Where:** `_too_nested`, `terms = 0` on `(`/`[`/`{`, on `)`/`]`/`}` and on `,`/`;`. The commit message says "nesting without brackets is bounded before Meta.parse too", and old Finding 3 suggested resetting only at `,`/`;`.
- **What goes wrong:**
  - **Bracketed operands:** a chain whose operands are bracketed never builds up a count. Each bracket resets it, while the bracket depth stays at 1. Right-associative chains (`^`, `->`, `=>`) recurse in the parser. Left-associative ones build deep `Expr`s.
  - **`;`-separated blocks:** keyword blocks separated by `;` nest without brackets, and the `;` resets the count.
- **Evidence** (`probes/probe_bypass_overflow.out`, `probe_bypass.out`, `probe_thresholds.out`). Each overflows the stack and then returns a String after 0.8–2.5 s:

  | Text | Overflows at | No overflow at |
  |:--|:--|:--|
  | `"begin; "^n * "1" * "; end"^n` | n = 2000 (24 KB) | n = 1500 |
  | `"if true; "^n …` | n = 2000 | |
  | `"(1)^"^n * "1"` | n = 10^4 (40 KB) | n = 5000 |
  | `"(a)->"^n * "1"` | n = 10^4 (50 KB) | |
  | `"(1)=>"^n` | n = 10^5 | |
  | `"(1)-"^n` | n = 10^5 | |
  | `"(x)'"^n` | n = 10^5 | |

- **Fix:**
  - Keep a count per bracket level: push on open, and on close restore the outer count plus one, so a bracketed operand is one term of the enclosing chain.
  - Reset only at `,` (and at `;` inside brackets, for hand-typed `[1 2; 3 4]`).
  - Count block keywords (`begin`, `let`, `if`, `for`, `while`, `try`, `quote`, `function`, `do`, …) as depth unless a `:` precedes them (`:begin` and `:end` are Symbols `val2str` writes), or refuse them.
  - Or use the tokenizer approach of Finding 1.
- **Test:**
  - `@test T("(1)^"^2000 * "1")`
  - `@test T("(a)->"^2000 * "1")`
  - `@test T("begin; "^2000 * "1" * "; end"^2000)`
  - keep the `Dict(Symbol("k", i) => -i …)` guard

## Per-item status of reviews/76c67a1.md

| Item | Status | Evidence |
|:--|:--|:--|
| 1. `_type_size` ignores `L` (78-char abort) | **FIXED.** All Finding 1 literals → String in ≤ 0.05 s, including `Pair{…}[]` and the two-level 256 form. `L` is counted for `SArray`/`MArray`, also with a free or non-numeric size. Valid static types still parse (`SMatrix{2, 2, Float64, 4}`, `SVector{1018, Float64}`, `SA[…]` keys). Non-integer `L` (`1.0e6`, `'a'`) gives inert types | `probe_static_length.out`, `probe_type_size.out` |
| 2. `'"'` and comments open strings | **PARTLY FIXED.** `'"'` is skipped, comments are refused, and the effect-B regression is gone: `Any['"', "("^40]`, `('"', "-"^1100)` and `('"', "x", "["^33)` round-trip again. Char lexing is still wrong for `'\''`, `'''` and long `\x` escapes, and strings are misread for `"""` and interpolation, with the same overflow (Finding 1) | `probe_review_literals.out`, `probe_parity.out`, `probe_bypass_overflow.out` |
| 3. Nesting without brackets, newline-split chains | **PARTLY FIXED.** Every literal of the finding is rejected before `Meta.parse` (0.0 s): adjoints, `$`, `begin`×3000, `a.a…`, `1-\n`, `2^\n`, `±`, `→`, `×`. Bracketed operands and `;`-separated blocks still get through (Finding 2) | `probe_review_literals.out`, `probe_bypass_overflow.out` |

Minor issues of that review:
- **Docs overclaim:** `docs/src/data.md` is reworded ("these limits bound what the parser computes and compiles for a text"). With Finding 1 of that review fixed, that statement holds. The docstring adds "long chains of operators or words, comments". The comment above `_too_nested` is partly inaccurate (see Minor issues below).
- **Depth > 32 and `Char['(']`×32 as intended differences:** unchanged. The docstring names the 32-level limit.
- **Triple-quoted typed text:** unchanged. `"""a"((((…40…"""` → `""a"((((…`, where the reference gives `a"((((…`.
- **Static arrays ≥ 1019 elements:** unchanged. They were already Strings in the reference, so nothing changes against main_dev.
- **Stale `author_probe_results.out`:** no new author probe file in this commit.

## Test coverage

- The 10 new `@test` lines separate the code: at 76c67a1, 2 crash or hang (exit 134, exit 124), 6 fail and 2 pass. The 2 that pass are guards (`SMatrix{2, 2, Float64, 4}`, the Char round trip).
- The `_too_nested` assertions are direct, as the old review asked, so a parser overflow can't pass them by returning a String.
- The Char round trip `Any['\'', '\\', 'é', "a'b"]` passes at 76c67a1 too. It doesn't detect the `'\''` misread, because `val2str` writes `, ` after the Char.
- No test covers `'\''` followed by `','`, `'''`, `"""`, interpolation, bracketed chains or `;`-separated blocks (Findings 1, 2).
- No `L` test with a non-integer `L` (harmless) and no `MArray` case. The `MArray` behaviour checks out (`probe_type_size.out`).
- Comments: the differential corpus has no hand-typed text with a comment, so the new behaviour change (below) isn't pinned as an intended difference.

## Minor issues

- **Comments refused: a behaviour change for hand-typed values.** `1 # c` and `1 #= c =#` gave `1` in the reference and at 76c67a1. Now they are Strings, and the hash text changes from `1` to `1 # c`. `val2str` never writes comments, and PDEStudio's CSV writer uses `val2str`, so stored and exported values are unaffected; only hand-edited CSV/editor values with a trailing comment change. The docstring mentions it, but the differential test's `refused` list doesn't. Alternative: strip `#…` to the end of the line instead of refusing.
- **One false rejection of `val2str` output:** non-ASCII, non-letter characters count as an operator each, even inside one identifier. `Symbol("x" * "′"^1100)` → String (the reference: Symbol). The same applies to `!`, subscripts and combining marks repeated more than 1024 times. The hash text is unchanged, and the value is contrived.
- **Comment of `_char_literal_end`:**
  - "the longest escape: `\U0010ffff`" is wrong. `repr` writes `'\xf0\x80\x80\x80'` (16 characters) for invalid Chars.
  - The docstring example list implies `'\''` is handled.
- **Comment above `_too_nested`:** "Outside of string and Char literals" misses that interpolation inside strings is parsed.
- **Commit message:** it overstates "nesting without brackets is bounded" (Finding 2).
- **`_MAX_OPERATORS`:** it now counts "terms"; the name is stale.
- **`_type_size` docstring-comment** (`:129-131`): it describes static array elements by size only. The `L` rule is only in the inner comment.

## Verdict

The commit closes the high-severity issue of reviews/76c67a1.md:
- `_type_size` counts the length parameter `L`, and the 78-character `Dict{SArray{Tuple{}, …, 0, 64}…}()` abort is gone. Every Finding 1 literal returns a String in ≤ 0.05 s, and valid static types still parse.
- The `'"'` / comment desync and its round-trip regression are fixed.
- Every bracket-free and newline-split chain of old Finding 3 is rejected before `Meta.parse`.

Hash stability holds:
- 4340 datasets, 149,850 values: 0 parse and 0 hash-text differences
- 95 synthetic `val2str` values: 1 contrived parse difference, 0 hash-text differences

`str2val` still evaluates no code. The suite passes 1117 / 1117, and the new tests fail or crash with 76c67a1's `src/`.

The text scanner still diverges from Julia's lexer (`'\''`, `'''`, long `\x` escapes, `"""`, `"$(…)"`), so 4 KB texts still overflow `Meta.parse`'s stack (Finding 1). Its count resets at every bracket and `;`, so bracketed chains and `;`-separated blocks overflow from 24 KB (Finding 2). Every one of them returns a String and the process keeps working, but the warning says program state may be corrupted.

Findings: 0 high, 1 medium (1), 1 low (2). Both are bypasses of the scanner the previous round asked for; neither is a regression in `val2str` round trips.

Per item of reviews/76c67a1.md:
- 1: fixed
- 2: partly fixed
- 3: partly fixed


The probes are in `reviews/29a9afa/`; `probes/lit/` (generated literals) and the scratch copy are not committed.
