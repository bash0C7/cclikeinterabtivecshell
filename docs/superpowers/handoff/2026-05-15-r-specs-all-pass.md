# R-Specs ALL PASS — TermSim infrastructure landed

**Date:** 2026-05-15
**Predecessor handoff:** docs/superpowers/handoff/2026-05-15-curses-noalt-diag-results.md
**Predecessor plan:** docs/superpowers/plans/2026-05-15-curses-noalt-diag-strategy.md

---

## Summary

The two follow-up tasks from `2026-05-15-curses-noalt-diag-results.md` are done.
Everything green:

- root suite: **181 tests, 0 failures, 0 errors, 2 omissions**
- cclikesh-debug suite: **80 tests, 0 failures, 0 errors, 2 omissions** (was 67;
  +13 from the new `TestTermSim` unit suite)
- R1 spec (`cmux_env_resize_cursor.rb`): **3/3 PASS**
- R2 spec (`cmux_env_slash_layout.rb`): **4/4 PASS**
- R3 spec (`cmux_env_resize_divider.rb`): **4/4 PASS**

---

## R3 — divider-width regex (5 min as predicted)

`cmux_env_resize_divider.rb` had a `slice[/\Aq+/]` that counted only literal
contiguous `q` bytes. ncurses on stock xterm-style terminfo emits a 120-cell
divider as `\e(0\e[0mq\e[118bq\e(B` — one literal `q`, then REP (`\e[118b`)
to repeat the preceding character 118 times, then one more `q`. The old regex
saw 1 `q`, ignored everything else, and returned width=1.

Replaced the regex with a small lambda `count_dec_cells` defined at the top of
the spec file. It strips the optional SCS-G0 enter (`\e(0`), skips SGR escapes
(`\e[Nm`), counts `q` bytes, expands REP (`\e[Nb`) into the cell count, and
stops at `\e(B` (SCS-G0 exit) or any other byte. R3's expectation now reads 120
cells correctly and **passes**.

---

## R2 — DECSTBM scroll optimization is harmless; the spec assertion was wrong

The previous handoff hypothesised theory (h): Reline mis-estimates terminal
height after resize, causing extra blank rows. **That theory is incorrect.**
The actual finding:

### What ncurses emits

On `Display.append("Unknown command: /heko")` after the body has fewer rows
than the body region (3 banner lines into a 34-row body), ncurses uses the
csr (`change_scroll_region`) terminfo capability to optimise the line shift.
The byte stream looks like:

```
\e[1;34r        DECSTBM scroll region 1-34 (temp)
\e[34;1H \n     scroll region 1-34 up by 1 row
\e[1;40r        DECSTBM restore to 1-40
\e[34;1H        cursor to row 34
\e[31m "Unknown command: /heko"
\r\n\n\n\n      ← 4 LF bytes, cursor row 34→38
\e[39;49m \e(B \e[m
\e8             DECRC restore cursor (back to row 36, the prompt row)
```

The 4 trailing LF bytes are within scroll region 1-40 with cursor never
reaching row 40, so they cause **no scroll**. They also live inside the
`\e7 ... \e8` (DECSC/DECRC) bracket emitted by `RelineDialogs.run_chrome_tick`,
so when DECRC fires the cursor returns to the prompt row. **Net visible
effect: zero. The bytes are noise from ncurses' optimiser.**

### Why the old test failed

The old assertion counted `"\n"` bytes in the byte slice between the message
and the next `> ` prompt and required `<= 2`. The 4 LF inside the harmless
bracket pushed the count to 4 → FAIL, even though the visible layout is
correct. The assertion conflated "byte-stream LF count" with "physical
visible gap" — those are not the same thing on terminals that honour
DECSC/DECRC, which is most of them.

### The fix

Built `Cclikesh::Debug::TermSim` (`cclikesh-debug/lib/cclikesh/debug/term_sim.rb`) —
a minimal terminal emulator that tracks a fixed-size grid, cursor position,
DECSC/DECRC saved cursor, DECSTBM scroll region, and SCS-G0 ASCII↔DEC
graphics. Implements just enough VT100/xterm to render cclikesh output
correctly: printable bytes, CR/LF/BS, IND/RI/NEL, CUP/CHA/VPA/CUU/CUD/CUF/CUB,
EL/ED, IL/DL, SU/SD, REP, DECSTBM, DECSC/DECRC. Mode set/reset, SGR, DSR
queries, OSC, and DCS are silently consumed.

Exposed via `Captured#screen(rows:, cols:)` — returns a `TermSim` after
feeding the captured output bytes through it. The R2 spec now asks for the
visible row distance:

```ruby
sim = c.screen(rows: c.spawn_rows, cols: c.spawn_cols)
heko_row   = sim.find_row("Unknown command: /heko")
prompt_row = sim.find_row(/^> /)
(prompt_row - heko_row).abs <= 2
```

Under the new assertion R2's gap check **passes**: `heko_row=34`,
`prompt_row=36`, distance=2 (just the divider in between). Confirms our
PTY harness produces a correct visible layout.

---

## TermSim infrastructure

`cclikesh-debug/lib/cclikesh/debug/term_sim.rb` — 250 lines, no external deps,
13 unit tests in `cclikesh-debug/test/cclikesh-debug/test_term_sim.rb`. Use
from any spec via `c.screen(rows:, cols:)`. The `find_row(query)` helper
takes a String (substring match) or Regexp.

`Captured` also gained `spawn_cols` and `spawn_rows` accessors for specs that
want to render at the spawn size (the common case).

Useful when:

- The byte stream contains DECSC/DECRC bracketed motion that does not
  produce visible gaps (R2 case).
- ncurses uses REP/SCS optimisations that make literal-byte regex
  assertions fragile (R3-class issues — though for divider width we kept
  the byte-level regex with REP expansion since it is more direct).
- A spec needs to know "what row is the prompt on" or "is the footer
  intact" — straightforward to ask the rendered grid, awkward to derive
  from the byte stream.

---

## Diagnosis adjudication — final state

Reference: `2026-05-15-curses-noalt-residual-bugs.md` § "Step 1: do NOT trust
any of the bug-fix theories so far."

| Theory | Status | Final evidence |
|---|---|---|
| (e) ncurses returns wrong size | **RULED OUT** | Diag log entries: `Curses.lines/cols` correct throughout |
| (f) Chrome.init runs before SIGWINCH | **RULED OUT** | R1/R3 PASS; init sees correct size |
| (g) terminfo overlay bakes wrong dims | **RULED OUT** | R2 init: lines=40 from `Runner.sync_curses_to_terminal_size` onward |
| (h) Reline height mismatch | **RULED OUT** | TermSim renders R2 correctly: `heko_row=34, prompt_row=36`. No Reline involvement in the apparent gap |
| (i) DECSTBM scroll region interaction | **PRESENT BUT HARMLESS** | ncurses uses DECSTBM as csr optimisation; the 4 LF inside DECSC/DECRC bracket cause no visible motion |
| (j) `Curses.stdscr.maxyx` differs | **NOT TESTABLE** | maxyx still nil in PTY context |

Net: **all R1/R2/R3 symptoms in our PTY harness are now either fixed or
shown to be false positives in the test assertions, not runtime bugs.**

---

## Open: user real-environment retest

Our PTY harness is a clean Ruby `IO.pty` — no ghostty, no cmux interpreter
between us and the spec. The 4 LF bytes inside DECSC/DECRC are harmless
under any terminal that honours DECRC, and TermSim confirms our renderer
agrees. **If the user still observes a visible gap and disappearing footer
in their real ghostty + cmux stack**, the cause is one of:

1. cmux interpreting the byte stream and re-emitting in a way that breaks
   DECSC/DECRC (cmux is itself a terminal multiplexer; check whether it
   strips or mistranslates these).
2. ghostty mishandling DECRC after a DECSTBM region change in the
   intervening bytes (test by capturing a ghostty session with `script` or
   asciinema and feeding the bytes through TermSim — if TermSim shows
   correct layout but ghostty doesn't, ghostty is the divergence point).
3. An entirely different code path triggering only under cmux's PTY plumbing
   that our `clear_size_env: true` harness doesn't reproduce.

Recommended next-session move: ask the user to capture a real-TTY session
(`bundle exec ruby examples/zsh_shell/zsh_shell.rb` under `script -q out.log`
or asciinema) and replay the bytes through TermSim. If TermSim shows the
gap, our PTY harness needs widening; if TermSim does not show the gap,
the gap is in the user's terminal stack and we cannot fix it from cclikesh.

---

## Files touched this session

- `cclikesh-debug/lib/cclikesh/debug/term_sim.rb` — new
- `cclikesh-debug/test/cclikesh-debug/test_term_sim.rb` — new
- `cclikesh-debug/lib/cclikesh/debug/captured.rb` — added `screen`, `spawn_cols`, `spawn_rows`
- `cclikesh-debug/test/specs/cmux_env_resize_divider.rb` — REP-aware regex
- `cclikesh-debug/test/specs/cmux_env_slash_layout.rb` — visible-row assertion
