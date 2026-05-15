# Curses + Non-Alt-Screen Residual Bugs — Self-Contained Diagnostic Strategy

**Date:** 2026-05-15
**Status:** Design (pre-plan)
**Companion handoff:** `docs/superpowers/handoff/2026-05-15-curses-noalt-residual-bugs.md`
**Predecessor specs:** `docs/superpowers/specs/2026-05-14-curses-noalt-redesign.md` (still valid)

---

## 1. Problem

Three residual rendering bugs persist on the user's native TTY (ghostty inside cmux) after the no-alt-screen + 3-region layout redesign landed:

- **R1**: After resize following a slash command, the visible cursor lands inside body text instead of on the prompt row.
- **R2**: After `/pwd` / `/heko`, body output is separated from the next prompt by many blank rows AND the 3-row footer (spinner / info_bar / shortcuts hint) disappears from view.
- **R3**: Resize does not reflow dividers to the new terminal width.

Four prior fix theories (cursor anchoring, `resize_term` typo, bottom-align, ENV LINES/COLUMNS overwrite) each green'd unit + PTY-spec but failed on the user's native TTY. The user's actual probe disproved the cmux-stale-env hypothesis behind commit `2b2db28`:

```
$ ruby -r io/console -e 'p [IO.console.winsize, ENV["LINES"], ENV["COLUMNS"], ENV["TERM"]]'
[[34, 90], nil, nil, "xterm-ghostty"]
```

So the real root cause remains unknown.

## 2. Why prior verification failed

Two structural traps caused four consecutive false-positive "fixed" handoffs (logged in `feedback_verify_before_handoff.md`):

1. **`cclikesh-debug/lib/cclikesh/debug/pty_runner.rb` `env_for_spawn` (l55-60)** unconditionally injects `COLUMNS`/`LINES` into the spawn env. The user's actual cmux env has both nil. PTY-spec runs therefore execute the child in a fundamentally different env from the user's reproduction case, and any bug whose root cause is sensitive to LINES/COLUMNS (presence, absence, or interaction with terminfo) is invisible to the spec.
2. **A self-rolled vt100 emulator (`/tmp/cclk-verify/render.rb`)** had a `\n`-outside-scroll-region bug, mis-rendering the byte stream and hiding the symptom. Custom emulators are too easy to misimplement and too hard to trust.

Any verification path that requires either (a) PTY runs with stale env unrepresented or (b) a custom emulator, will keep producing false positives.

## 3. Constraints (hard requirements from this round)

- **No human-in-the-loop verification.** The user explicitly forbade asking them to run probes, share log files, or eyeball symptoms. All verification must run as part of `bundle exec rake test`.
- **No custom terminal emulator.** Any byte-stream judgment must use grep-able byte invariants, not screen reconstruction.
- **Must reproduce the user's actual env conditions inside our own test harness.** Specifically: `ENV["LINES"]` and `ENV["COLUMNS"]` must be absent in the spawned child while `IO.console.winsize` returns the intended size via TIOCGWINSZ.
- **Must run on every `rake test`.** Once added, R1/R2/R3 cannot regress without a CI failure.

## 4. Design

Three composable additions, each independently useful and each carrying its own assertion surface. They combine into a self-contained reproduction-and-verification path that runs entirely inside `rake test`.

### 4.1 `PtyRunner` — `clear_size_env:` mode

Default behaviour stays as-is (existing specs unchanged). New constructor keyword `clear_size_env: true` switches `env_for_spawn` to **delete** `LINES` / `COLUMNS` from the merged env instead of overwriting them. The PTY size is communicated to the child purely via `@r.winsize = [@rows, @cols]` (already happening), so the child must derive its size from TIOCGWINSZ — exactly the user's cmux conditions.

`SpecDSL::SessionScope#spawn` (`cclikesh-debug/lib/cclikesh/debug/spec_dsl.rb` l26-29) gains a `clear_size_env: false` kwarg. `SpecDSL.run` (l66-103) forwards it into the `PtyRunner.new` keyword args. New regression specs opt in; existing specs do not.

**Why:** Removes verification trap #1. Without this, R1/R2/R3 cannot be reproduced inside the harness because the child gets non-nil LINES/COLUMNS.

### 4.2 `PtyRunner` — `script_resize(cols, rows)` API

New `ScriptApi` method that calls `@r.winsize = [rows, cols]` (note: `IO#winsize=` takes `[rows, cols]` per `io/console`; the public API takes `(cols, rows)` to mirror the existing `cols, rows` pairing in `PtyRunner.new`). Setting winsize on the master end causes the kernel to deliver SIGWINCH to the child process group. This makes resize a first-class spec primitive instead of an out-of-band manual step.

`SessionScope` gains a `resize(cols, rows)` step that pushes `[:resize, cols, rows]` onto `@steps`, dispatched in `SpecDSL.run`'s case branch alongside `:wait` / `:send`.

Used in R1 / R3 specs to fire a real resize event between user inputs and observe the post-resize byte stream.

**Why:** R1 and R3 are resize-triggered. Without an in-spec way to fire SIGWINCH, those bugs cannot be reproduced under `rake test`.

### 4.3 In-process diagnostic log — `CCLIKESH_LAYOUT_DIAG`

When `ENV["CCLIKESH_LAYOUT_DIAG"]` is set (its value is the absolute path of the log file to append to), the runner/chrome/display modules append a structured line to that file at every layout-affecting call site:

```
[<iso8601 ts>] <tag> curses.lines=<N> curses.cols=<N> maxyx=<R,C> winsize=<R,C> env_lines=<v> env_cols=<v>
```

Call sites (one `Cclikesh::LayoutDiag.log("<tag>")` invocation each):

- `Runner.init_curses` — after `Curses.init_screen`
- `Runner.sync_curses_to_terminal_size` — after `Curses.resizeterm`
- `Chrome.init` — entry
- `Chrome.draw_dividers` — entry (so we can correlate the divider write with the value of `Curses.cols` at that exact tick)
- `Chrome.handle_resize` — entry AND after the `resizeterm` call
- `Display.refresh` — entry

The log is opt-in (envvar gated; path-as-value not boolean), low-volume (one line per layout-affecting call), and the spec wrapper picks the path so specs can read it deterministically.

Spec wrapper (`SpecDSL.run`):

- Computes a per-session diag log path: `File.join(Dir.tmpdir, "cclikesh-diag-#{uuid}.log")`. Per-session paths avoid contention if specs ever parallelise and remove the need for pre-spawn truncation.
- Injects `CCLIKESH_LAYOUT_DIAG=<path>` into the spawn env (in addition to honoring `clear_size_env: true`). `LayoutDiag.log` reads the path from the env var; if the var is absent or empty, it is a no-op. Production runs are therefore unaffected.
- After the child exits, reads the diag log file and parses each line into `{ts:, tag:, lines:, cols:, maxyx:, winsize:, env_lines:, env_cols:}`. The parsed array is passed to `Captured.from_storage` as a new keyword arg `diag_entries:` and exposed as `captured.diag_entries`. `Captured#initialize` freezes the array for safety alongside the other pre-computed fields.

**Why:** When R1/R2/R3 reproduces, the diag log tells us EXACTLY which `Curses.lines`/`Curses.cols`/`maxyx` value was wrong and at which call site. This converts vague "still buggy" into a structured signal we can write asserts against (e.g. "after `script_resize(120, 40)`, the next `Chrome.handle_resize` entry must show `curses.cols=120`"). It also doubles as a forensic audit log for any future layout regression.

### 4.4 Three new regression specs

Each opts into `clear_size_env: true` (the SpecDSL kwarg). The diag log path is wired automatically by `SpecDSL.run` (specs do not set `CCLIKESH_LAYOUT_DIAG` themselves). Each asserts byte-stream invariants (no emulator) and diag-log invariants.

- **`cclikesh-debug/test/specs/cmux_env_resize_cursor.rb`** (R1)
  - Send `/heko\r`. Wait for echo. `script_resize(80, 40)`. Wait. Send `\C-c` then `/q\r`.
  - Byte assertions:
    - The last `\e[<row>;<col>H` cursor-position sequence emitted before quit places the cursor on the prompt row, computed as `final_curses_lines - Chrome::FOOTER_HEIGHT - 1`. The "final_curses_lines" comes from the last diag-log entry.
  - Diag assertions:
    - There is at least one `Chrome.handle_resize` log entry after the `script_resize`, and its post-resizeterm `curses.lines`/`curses.cols` match the requested 40/80.

- **`cclikesh-debug/test/specs/cmux_env_slash_layout.rb`** (R2)
  - Send `/pwd\r`. Wait. Send `/heko\r`. Wait. Send `/q\r`.
  - Byte assertions (run against `captured.output_bytes`):
    - The tail of the byte stream (last 4 KiB before the `/q` echo) contains at least one occurrence of a `Chrome::SPINNER_GLYPHS` byte (`*` or `+`). This proves the footer was painted within the final visible frame.
    - In the same tail, between the substring `Unknown command: /heko` (the `/heko` body output) and the last `> ` prompt, the count of `\n` bytes is `<= 2`. More than 2 indicates the large vertical gap symptom of R2.
  - Diag assertions:
    - Every `Display.refresh` entry between `/pwd` and quit shows `curses.lines >= 10` (sanity: the body region wasn't computed against a 0/24 default).
    - The maximum `curses.lines` across all `Display.refresh` entries equals the spawn `rows:` value (proves curses sees the real winsize, not a terminfo default).

- **`cclikesh-debug/test/specs/cmux_env_resize_divider.rb`** (R3)
  - Spawn at `cols: 80, rows: 24`. Send empty `\r` (no-op input to ensure first draw happened). Wait. `script_resize(120, 30)`. Wait 0.5 s for SIGWINCH propagation + redraw. Send `/q\r`.
  - Byte assertions (run against `captured.output_bytes` slice from the byte index of the last `Chrome.handle_resize` diag entry's emitted CUP sequence onward):
    - Locate the divider redraw in the post-resize tail by finding `\e[<row>;1H` where `<row>` matches one of the two divider rows reported in the post-resize diag entry (`lines - FOOTER_HEIGHT - 3` or `lines - FOOTER_HEIGHT - 1`). The byte slice between that CUP and the next CSI escape (or 200-byte cap, whichever first) MUST be exactly `cols` bytes long when interpreted as printable cells. The expected payload is either (a) `\e(0` then `q`*cols then `\e(B` (DEC line drawing under stock xterm-style terminfo) OR (b) `q`*cols when ACS is active without SO/SI bracketing. The spec accepts either form by counting `q` runs after stripping a leading `\e(0` and trailing `\e(B`. Anything other than `cols` (specifically not 80, the pre-resize value) fails the spec.
  - Diag assertions:
    - The post-resize `Chrome.draw_dividers` entry shows `curses.cols == 120 && curses.lines == 30`.
    - The `Chrome.handle_resize`-after entry's `winsize` field equals `[30, 120]`.

### 4.5 `Cclikesh::LayoutDiag` module shape

```ruby
# lib/cclikesh/layout_diag.rb
require "time"

module Cclikesh
  module LayoutDiag
    def self.log(tag)
      path = ENV["CCLIKESH_LAYOUT_DIAG"]
      return if path.nil? || path.empty?
      require "curses" unless defined?(Curses)
      lines  = Curses.lines  rescue nil
      cols   = Curses.cols   rescue nil
      maxyx  = (Curses.respond_to?(:stdscr) && Curses.stdscr ? Curses.stdscr.maxyx : nil) rescue nil
      winsz  = (require "io/console"; (IO.console&.winsize)) rescue nil
      env_l  = ENV["LINES"]
      env_c  = ENV["COLUMNS"]
      File.open(path, "a") do |f|
        f.puts "[#{Time.now.iso8601(3)}] #{tag} curses.lines=#{lines.inspect} curses.cols=#{cols.inspect} maxyx=#{maxyx.inspect} winsize=#{winsz.inspect} env_lines=#{env_l.inspect} env_cols=#{env_c.inspect}"
      end
    rescue StandardError
      nil # Best effort; never raise from a debug log site.
    end
  end
end
```

- File open uses mode `"a"` (`O_APPEND`); single-line writes are well under `PIPE_BUF` (4 KiB on macOS) so concurrent appends from main + handler Ractors remain atomic per-line.
- All exception paths swallow; this module must never affect runtime behaviour even if disk fills or path is unwritable. (Aligns with `~/dev/src/CLAUDE.md` "No Silent Exception Swallowing" — exception is acceptable here because the module's contract IS "best effort, debug-only, never affect production"; the rescue is justified by that explicit contract, not as silent error masking.)

### 4.6 Combined verification flow

1. Run `bundle exec rake test` from repo root and from `cclikesh-debug/`.
2. The new specs reproduce R1/R2/R3 in cmux-like env.
3. If any assertion fails, the diag log identifies which Curses value was wrong at which call site, and that pinpoints the root cause among theories (e)–(j) in the handoff doc.
4. Apply the targeted fix.
5. Re-run `rake test`. All specs (existing + new R1/R2/R3) must green.
6. Hand off — the green state is now logically equivalent to "works in user's env" because the spec env matches the user's env conditions.

## 5. Out of scope

- The fix itself for R1/R2/R3. This spec only delivers the **diagnostic + verification infrastructure** that makes a real fix possible. The fix becomes a follow-up plan once the diag log identifies the root cause.
- PTY recording → mp4/mov export (handoff doc §"Pending follow-up specs").
- Autonomous terminal automation outside PTY (handoff doc §"Pending follow-up specs").
- Refactoring of unrelated PtyRunner internals.

## 6. Files touched

New:
- `lib/cclikesh/layout_diag.rb` — `Cclikesh::LayoutDiag.log(tag)` module.
- `cclikesh-debug/test/specs/cmux_env_resize_cursor.rb`
- `cclikesh-debug/test/specs/cmux_env_slash_layout.rb`
- `cclikesh-debug/test/specs/cmux_env_resize_divider.rb`

Modified:
- `lib/cclikesh/runner.rb` — `require_relative "layout_diag"`; wire `LayoutDiag.log` at: after `Curses.init_screen` in `init_curses`, after `Curses.resizeterm` in `sync_curses_to_terminal_size`.
- `lib/cclikesh/chrome.rb` — `require_relative "layout_diag"`; wire `LayoutDiag.log` at entry of `Chrome.init`, entry of `Chrome.draw_dividers`, entry of `Chrome.handle_resize`, and after the `Curses.resizeterm` call inside `handle_resize`.
- `lib/cclikesh/display.rb` — `require_relative "layout_diag"`; wire `LayoutDiag.log` at entry of `Display.refresh`.
- `cclikesh-debug/lib/cclikesh/debug/pty_runner.rb` — add `clear_size_env:` kwarg to `initialize`; thread it into `env_for_spawn` (delete LINES/COLUMNS instead of overwriting); add `ScriptApi#resize(cols, rows)` and `PtyRunner#script_resize(cols, rows)` that calls `@r.winsize = [rows, cols]`.
- `cclikesh-debug/lib/cclikesh/debug/spec_dsl.rb` — `SessionScope#spawn` accepts `clear_size_env: false`; `SessionScope#resize(cols, rows)` pushes `[:resize, cols, rows]`; `SpecDSL.run` forwards `clear_size_env:` into `PtyRunner.new`, dispatches `:resize` via `api.resize`, computes per-session diag log path, sets `CCLIKESH_LAYOUT_DIAG=<path>` in spawn env, parses the file post-spawn, and passes `diag_entries:` into `Captured.from_storage`.
- `cclikesh-debug/lib/cclikesh/debug/captured.rb` — `from_storage` accepts `diag_entries: []` kwarg; `initialize` stores and freezes `@diag_entries`; `attr_reader :diag_entries`.

## 7. Acceptance criteria

- `bundle exec rake test` (root) green.
- `cd cclikesh-debug && bundle exec rake test` green.
- New specs `cmux_env_*` either fail (revealing R1/R2/R3 in-harness, with diag log indicating the wrong Curses value) OR green (proving R1/R2/R3 are not reproducible in the same env conditions as the user — which would invalidate the cmux-env hypothesis and demand a different probe). Either outcome is informative; an "all green" outcome here is acceptable for THIS spec because it would mean the diag infrastructure works and the bug lies elsewhere, which is a legitimate finding worth handing off.
- The diag log produced during the new specs is non-empty and parseable.
- `clear_size_env: true` mode in PtyRunner verifiably leaves `LINES`/`COLUMNS` unset in the child (assert via a tiny throwaway spec that runs `printenv`).

## 8. Risks & mitigations

- **Risk:** New specs green and the bug is still reproducible only in the user's actual TTY.
  - **Mitigation:** That outcome by itself is information — it rules out the cmux-env hypothesis and the next session can pivot to ghostty-specific theories (terminfo entry inspection, OSC sequences). The diag log infra remains useful.
- **Risk:** Diag log path collides between concurrent specs.
  - **Mitigation:** Spec wrapper computes a per-session path (`Dir.tmpdir/cclikesh-diag-#{uuid}.log`); collisions are impossible.
- **Risk:** Adding diag log overhead changes timing enough to mask a race.
  - **Mitigation:** Diag log is no-op unless `CCLIKESH_LAYOUT_DIAG` is set; production / normal-spec runs unaffected.
- **Risk:** The user's actual env has additional differences (e.g. specific TERMINFO entry contents) that the harness still doesn't reproduce.
  - **Mitigation:** This is acknowledged. If new specs green but the bug persists in user's TTY, the diag log + `clear_size_env` infra still narrows the search — next iteration targets terminfo or ghostty-specific behaviour.
