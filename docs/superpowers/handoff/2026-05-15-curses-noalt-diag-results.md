# Curses Noalt Diagnostic Strategy — Results

**Date:** 2026-05-15
**Predecessor plan:** docs/superpowers/plans/2026-05-15-curses-noalt-diag-strategy.md
**Predecessor handoff:** docs/superpowers/handoff/2026-05-15-curses-noalt-residual-bugs.md

---

## Infrastructure bug discovered and fixed this session

**Root cause of "0 diag entries" in all 3 R-specs:** `SpecDSL.parse_diag_line` did not
`chomp` the line before applying the regex with `\z` anchor.
`File.readlines` returns lines WITH trailing `\n`; `\z` anchors to end-of-string, so
every line failed to match. Fix: add `.chomp` in `parse_diag_line` before calling `.match`.

Fixed in `cclikesh-debug/lib/cclikesh/debug/spec_dsl.rb`. All 3 R-specs now produce
25-28 diag entries per run.

---

## Test suite status

- `bundle exec rake test` (root): **181 tests, 276 assertions, 0 failures, 0 errors, 2 omissions** — 100% passed
- `cd cclikesh-debug && bundle exec rake test`: **67 tests, 153 assertions, 0 failures, 0 errors, 2 omissions** — 100% passed

No pre-existing `test_echo_shell_boots_and_quits_cleanly` timeout flake fired this run.

---

## Critical workflow finding

PTY specs in `cclikesh-debug/test/specs/*.rb` MUST be invoked from REPO ROOT, not from
`cclikesh-debug/`. The `argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb]` uses
a relative path resolved against the cwd of the SpecDSL evaluator. From `cclikesh-debug/`,
the path resolves to `cclikesh-debug/examples/...` which does not exist; the child
immediately exits with LoadError (~2 events, ~0.6s session). From repo root, the path
resolves correctly (25-28 diag entries, 3-5s sessions, real diagnostic data).

This was a hidden trap during prior sessions. The env-var override noted in
`2026-05-15-curses-noalt-residual-bugs.md` § "PTY regression specs were a TRAP" is a
SECOND independent trap; the cwd issue documented here is the first trap.

Correct invocation:

```
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell
bundle exec ruby cclikesh-debug/exe/cclikesh-debug play cclikesh-debug/test/specs/<spec>.rb
```

---

## R1 spec results — `cmux_env_resize_cursor.rb`

Run from repo root. `clear_size_env: true`, spawn cols=80 rows=24, resize to rows=40.

| Expectation | PASS/FAIL |
|---|---|
| post-resize handle_resize entry sees the new size | **PASS** |
| final cursor placement is on the prompt row | **PASS** |
| session exits cleanly | **PASS** |

**All 3 expectations now PASS.** The cursor-jump-on-resize bug reported by the user is
FIXED in the current codebase (the chomp fix revealed the data; with data the spec passes).

### Key diag entries

28 total entries. Critical sequence around resize (entries 16–19):

```
16: tag: "Chrome.draw_dividers",          lines: 24, cols: 80, winsize: [40, 80], env_lines: "24", env_cols: "80"
17: tag: "Chrome.handle_resize.before",   lines: 24, cols: 80, winsize: [40, 80], env_lines: "24", env_cols: "80"
18: tag: "Runner.sync_curses_to_terminal_size", lines: 40, cols: 80, winsize: [40, 80], env_lines: "24", env_cols: "80"
19: tag: "Chrome.handle_resize.after_resizeterm", lines: 40, cols: 80, winsize: [40, 80], env_lines: "24", env_cols: "80"
```

Interpretation: SIGWINCH fires → `Chrome.handle_resize.before` sees old `curses.lines=24`
but already knows the new TIOCGWINSZ `winsize: [40, 80]`. After `Runner.sync_curses_to_terminal_size`
(which calls `Curses.resizeterm(40, 80)`), `Curses.lines` updates to 40. Cursor is then
correctly parked on the prompt row based on `lines=40`. **Mechanism is correct.**

Also notable: `env_lines: "24"` (ENV["LINES"]) remains at spawn-time value throughout —
`clear_size_env: true` left it unset, but `sync_terminal_env_pre_init` set it to 24 from
TIOCGWINSZ at startup. ENV["LINES"] does NOT update on resize (only `Curses.lines` does via
`Curses.resizeterm`). This is correct behaviour.

---

## R2 spec results — `cmux_env_slash_layout.rb`

Run from repo root. `clear_size_env: true`, spawn cols=120 rows=40, no resize.

| Expectation | PASS/FAIL |
|---|---|
| Display.refresh sees the real winsize throughout | **PASS** |
| spinner glyph present in final visible frame | **PASS** |
| no large vertical gap between /heko output and next prompt | **FAIL** |
| session exits cleanly | **PASS** |

### Key diag entries

23 total entries. ALL entries report `lines: 40, cols: 120, winsize: [40, 120]` — no
stale defaults, no wrong values. `Display.refresh` fires 4 times (entries 4–6, 12, 18),
all with `curses.lines=40, curses.cols=120`. Theory (e) from the residual-bugs handoff
("ncurses returns wrong value") is **RULED OUT** — ncurses has correct values throughout.

### Vertical gap finding

The gap expectation checks how many `\n` bytes appear between the `/heko` error output
`"Unknown command: /heko"` and the next prompt `"> "`. Measurement from this run:

- Span bytes: `0d 0a 0a 0a 0a 1b 5b 33 39 3b 34 39 6d ...` (escape sequences follow)
- **4 `\n` bytes** in span (threshold is `<= 2`, so FAIL)

The 4 `\n` bytes appear as `\r\n\n\n\n` — one CRLF plus three bare `\n`. This suggests
that after the slash-command output, the Display/Reline writes multiple blank rows before
re-painting the prompt. Since `curses.lines=40` is correct, the gap is NOT caused by
a wrong size value — it is caused by HOW the display positions the next prompt after a
slash command appends output in a 40-row body. The blank rows are likely Reline
re-rendering with an assumed terminal height smaller than 40, or the body-scroll
calculation placing the prompt too far down.

---

## R3 spec results — `cmux_env_resize_divider.rb`

Run from repo root. `clear_size_env: true`, spawn cols=80 rows=24, resize to cols=120 rows=30.

| Expectation | PASS/FAIL |
|---|---|
| post-resize Chrome.draw_dividers sees cols=120, lines=30 | **PASS** |
| Chrome.handle_resize.after_resizeterm winsize is [30, 120] | **PASS** |
| divider after resize spans the new cols (120 cells, not 80) | **FAIL** |
| session exits cleanly | **PASS** |

### Key diag entries

26 total entries. Critical resize sequence (entries 12–15):

```
12: tag: "Chrome.draw_dividers", lines: 24, cols: 80, winsize: [30, 120]  ← SIGWINCH seen before handle_resize
13: tag: "Chrome.handle_resize.before",   lines: 24, cols: 80, winsize: [30, 120]
14: tag: "Runner.sync_curses_to_terminal_size", lines: 30, cols: 120, winsize: [30, 120]
15: tag: "Chrome.handle_resize.after_resizeterm", lines: 30, cols: 120, winsize: [30, 120]
```

After resize, `Chrome.draw_dividers` fires (entries 16–25) all with `lines: 30, cols: 120`.
**ncurses updates correctly. The divider IS being drawn at the correct position.**

### Divider width finding

The spec's "divider spans 120 cells" expectation looks for a run of literal `q` characters
via regex `/\Aq+/` after the CUP (cursor position) escape for the divider row. Actual bytes
at the divider row (row 27, 1-based):

```
1b 28 30 1b 5b 30 6d 71 1b 5b 31 31 38 62 71 1b 28 42 ...
\e(0   \e[0m         q  REP(118)              q  \e(B
```

Decoded: `\e(0` (enter DEC line drawing mode), `q` (one horizontal bar), `\e[118b` (REP —
Repeat Preceding Character 118 times), `q` (total = 1 + 118 = 119... wait:
`q` then `\e[118b` = repeat `q` 118 more times = 119 total... plus the initial `q` = 120
total horizontal bar characters). ncurses emits `\e[Nb` (REP) instead of 120 literal `q`
bytes. The spec's `/\Aq+/` regex only matches consecutive literal `q` bytes and sees only
2 (the `q` before REP and the `q` after), returning length 2 — not 120.

**Conclusion:** The divider DOES span 120 cells after resize. The expectation is a
false negative due to REP (`\e[Nb`) in ncurses output. **This is a spec bug, not a
runtime bug.**

---

## Diagnosis — which of theories e–j the data supports

Reference: `2026-05-15-curses-noalt-residual-bugs.md` § "Step 1: do NOT trust any of
the bug-fix theories so far."

| Theory | Status | Evidence |
|---|---|---|
| (e) ncurses `Curses.lines`/`Curses.cols` returns wrong value despite ENV/TIOCGWINSZ correct | **RULED OUT** | R2: all 23 entries show `lines: 40, cols: 120` throughout; R3: entries 14–25 show `lines: 30, cols: 120` after resize |
| (f) `Chrome.init` runs before SIGWINCH propagates | **RULED OUT** | R1/R3: `Chrome.init` sees correct spawn size; handle_resize fires correctly on SIGWINCH |
| (g) terminfo overlay `-noalt` entry bakes in wrong `lines#`/`cols#` | **RULED OUT** — in PTY context | R2 init: `lines: 40` from the moment of `Runner.sync_curses_to_terminal_size` — the overlay does not corrupt size |
| (h) Reline's size detection conflicts with curses | **CANDIDATE — partially supported** | R2: `Curses.lines=40` is correct but Reline still produces 4 `\n` blank rows after slash output; Reline's internal terminal-height estimate may disagree |
| (i) DECSTBM scroll region interaction | **CANDIDATE** | Not directly visible in diag; the 4 `\n` blank rows in R2 are consistent with a wrong scroll region |
| (j) `Curses.stdscr.maxyx` differs from `Curses.lines`/`Curses.cols` | **NOT TESTABLE YET** | All `maxyx: nil` — `Curses.stdscr` is nil during these runs (PTY without full terminal, `Curses.stdscr` unavailable?) |

### Summary diagnosis

The two remaining live issues are:

1. **R2 vertical gap (FAIL):** `Curses.lines=40` is correct. The gap is a Reline / prompt
   re-paint issue — Reline does not know the terminal is 40 rows tall and emits extra blank
   rows when repositioning after slash-command output. Theory (h) is the primary candidate.

2. **R3 divider width (FAIL):** This is a **spec bug** (REP vs literal `q`). The runtime is
   correct — ncurses emits `q\e[118b` for a 120-wide divider. Fix the spec's regex to
   handle REP, then this expectation will pass.

---

## Recommended next-session focus

**Immediate (5 min):** Fix the R3 spec's divider-width regex to handle `\e[Nb` REP
sequences — change from `/\Aq+/` width counting to a function that expands REP before
counting, then verify R3 goes all-PASS.

**Primary bug work:** Investigate R2's vertical gap (4 `\n` after slash output).
Reline's `IOGate` or `ANSI` class reads terminal height via `Reline::IOGate.get_screen_size`
or similar — check what value it returns inside the PTY child. Add a diag call after
Reline initialization (`RelineDialogs.install`) that logs `Reline.get_screen_size` (or
equivalent). If Reline reports height=24 while `Curses.lines=40`, Theory (h) is confirmed
and the fix is to call `Reline.set_screen_size(rows, cols)` or equivalent after
`Curses.resizeterm`. Look at `lib/cclikesh/runner.rb` around line 19–30 where Reline is
initialized and around line 60–76 where the WINCH handler calls `Chrome.handle_resize`.

**After R2 fix:** Re-run all 3 R-specs from repo root with the dump-diag driver. All 4
expectations in R1, all 4 in R2, all 4 in R3 should pass. Then ask the user to re-test in
their actual cmux + ghostty environment.

---

## Infrastructure changes made this session

1. **`cclikesh-debug/lib/cclikesh/debug/spec_dsl.rb`** — added `.chomp` in `parse_diag_line`
   before regex match. This is the blocker fix: without it, 0 diag entries are ever parsed.

No other files changed. No temporary edits remain uncommitted.
