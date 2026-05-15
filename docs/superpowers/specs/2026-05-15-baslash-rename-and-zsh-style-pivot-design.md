# baslash: Rename + zsh-style + title-bar pivot

**Date:** 2026-05-15
**Predecessor handoff:** docs/superpowers/handoff/2026-05-15-r-specs-all-pass.md
**Predecessor specs:** docs/superpowers/specs/2026-05-09-cclikesh-design.md, 2026-05-14-curses-noalt-redesign.md

---

## 1. Problem statement

The current `cclikesh` (Claude-Code-Like Shell) gem has reached a point where
its architectural commitments work against its own goals:

1. **Scrollback truncation (discovered 2026-05-15).** ncurses uses DECSTBM
   (`change_scroll_region`) as a sub-region scroll optimization for the body
   pad. Rows scrolled out of the sub-region are never delivered to terminal
   scrollback — they are discarded. As a session lengthens, the user's
   ability to scroll back through past output silently degrades, even though
   their terminal scrollback buffer has plenty of room.
2. **Layout artifacts.** Multiple curses windows (Pad + Window + stdscr) plus
   Reline cursor management require an `\e7`/`\e8` DECSC/DECRC dance and a
   `TerminfoOverlay` hack to suppress alt-screen. Footer rows occasionally
   disappear, dividers desync on resize, prompt-row cursor parking is fragile.
3. **Identity drift.** The "Claude-Code-like" positioning implies a fixed
   visual footer with thinking bar / spinner / status — features that
   inherently fight against terminal-native scrollback. Two of the three
   identity-defining symptoms (footer + scrollback) cannot both succeed
   under any conventional terminal model without significant custom
   rendering. Claude Code itself paid in regressions when it moved off
   curses-style rendering.

The author has stated the project's true goal as: a Ruby framework for
slash-command-driven embedded DSLs (echo_shell, zsh_shell, irb_shell, and
future shells in the same scope), reaching practical-use quality. The
"Claude Code lookalike" positioning is no longer the goal.

## 2. Decision: rename and pivot

The project will be renamed to **`baslash`** ("ba" + "slash" — bash0C7's
slash-command-centric framework). This rename is intentional: it severs the
"Claude Code lookalike" expectation and frees the design to choose the
simplest model that meets the practical goal.

The visual model pivots from "fixed footer + sub-region body" to
"natural-flow zsh-style + terminal title bar status".

## 3. Design goals

- **Practical-use stability.** No silent data loss (scrollback works), no
  visible layout artifacts during a normal session, no corruption on resize.
- **Implementation simplicity.** The gem itself should be slim; complexity
  belongs in user code (the embedded DSLs).
- **Reuse battle-tested abstractions.** Reline (CRuby bundled) for line
  editing, dialogs, and history. Native terminal scrollback. OSC 0/2 for
  status. No custom terminal abstraction.
- **Targeted scope.** Practical-use means: medium-length sessions (up to a
  few hundred body lines), main terminals (ghostty, iTerm2, Terminal.app,
  cmux, tmux), CRuby 4.x, macOS first. Do not promise full Linux console /
  Windows Terminal coverage in v1; revisit in v2.
- **No backwards compatibility.** All implementations are author-owned and
  in the `examples/` tree; breaking-change rename + API churn is acceptable.

## 4. Why pivot away from curses

| Curses model expectation | baslash requirement | Resolution |
|---|---|---|
| Owns the alt-screen | Keep host scrollback intact | Pivot away — natural flow |
| Sub-region (DECSTBM) scroll for body | Body content reaches terminal scrollback | Pivot away — full-screen scroll |
| Byte-oriented `addstr` (macOS non-widec) | UTF-8 multi-byte rendering | Pivot away — `puts` to stdout |
| Cell-buffer diff optimizer | Predictable, debuggable byte stream | Pivot away — known byte sequences |
| Color pair allocation via `init_pair` | Static SGR colors | Pivot away — direct SGR strings |

The friction is structural. "Use curses correctly" means "accept alt-screen",
which means losing scrollback for body — which is one of the bugs we are
trying to fix. The pivot resolves all five rows simultaneously.

## 5. Visual model (zsh-style + title bar)

### 5.1 Screen composition

```
[terminal title bar]: ✻ working · 12s · 📁 ~/dev/baslash      <- OSC 0/2 set title

═══════════════════════════════════════════════════════════
[scrollback area: every byte ever written, terminal-native]

✻ baslash example: zsh-shell v0.2.1
  Ruby 4.0.3
  cd/export intercepted · /exit to quit
/help for commands · /exit · /pwd · /env · /reset
> /pwd
/Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell
> /heko
Unknown command: /heko
> _                                                          <- Reline-managed prompt
═══════════════════════════════════════════════════════════
```

### 5.2 Element responsibilities

| Element | Where rendered | Who renders it | When |
|---|---|---|---|
| Banner (boot greeting) | Inline at top of session, becomes scrollback | `Display.append` (boot-time `puts`) | Once at session start |
| Shortcuts hint | Inline (right after banner), becomes scrollback | `Display.append` | Once at session start |
| Past prompts + commands | Inline, becomes scrollback | Reline echo + Ractor `:append` messages | Per command |
| Past command outputs | Inline, becomes scrollback | `Display.append` from command handlers | Per command |
| Status (cwd, var count, phase, spinner) | Terminal title bar | `TitleBar.tick` from `Reline.periodic_tick` | Every 200 ms while idle |
| Current prompt + input editing | Bottom of screen (current cursor) | `Reline.readmultiline` | During input |

### 5.3 Why this fixes the bugs

- **Scrollback works:** Body content is `puts`'d to stdout. Each `\n` at the
  bottom row scrolls the screen; the row that goes off the top is added to
  terminal scrollback by every conformant terminal. No DECSTBM, no
  sub-region scroll, no row loss.
- **No layout artifacts:** No fixed footer means no footer-position
  calculation, no divider redraw on resize, no `\e7`/`\e8` dance, no
  `Curses.stdscr.touch` ordering.
- **Resize is trivial:** Reline observes SIGWINCH and re-renders its own
  prompt at the next opportunity. The status line is in the title bar
  (not on screen), so it does not depend on screen size.
- **Spinner without screen real estate:** `\e]0;<text>\a` (OSC 0 set window
  title) is universally supported across xterm-derived terminals and tmux
  (with `set-window-option allow-rename on`). Updating every 200 ms is cheap.

## 6. Module-by-module diff

### 6.1 Removed entirely

| File | LOC (current) | Reason |
|---|---:|---|
| `lib/cclikesh/chrome.rb` | ~230 | Footer / divider / sweep colors all removed |
| `lib/cclikesh/terminfo_overlay.rb` | ~162 | No curses → no smcup to strip |
| `lib/cclikesh/layout_diag.rb` | ~40 | No curses state to log |
| `lib/cclikesh/reline_idle_patch.rb` (Chrome integration) | ~30 (partial) | No `Chrome.handle_resize` to call |
| `Curses` calls in `runner.rb` (init_curses / teardown_curses) | ~80 | No curses init/teardown |
| `Display.@pad` infrastructure inside `display.rb` | ~70 | `puts` replaces `noutrefresh` |
| `Style.with(window, ...)` curses-window wrappers | ~30 | Direct SGR strings |

**Total removed: ~640 LOC.** Plus the `curses` gem dependency entirely.

### 6.2 Added

| File | LOC (estimated) | Purpose |
|---|---:|---|
| `lib/baslash/title_bar.rb` | ~50 | OSC 0/2 set/restore title; `tick(phase, ctx)` |
| `lib/baslash/style.rb` | ~50 | SGR helper (`Style.bold(s)` → `"\e[1m#{s}\e[0m"`) |
| `lib/baslash/display.rb` (rewritten) | ~60 | `append` / `live_slot` via `puts` + `\r\e[K` |
| `lib/baslash/runner.rb` (rewritten slim) | ~100 | Signal trap, Reline orchestration, main loop |

**Total added: ~260 LOC.**

### 6.3 Preserved (renamed `Cclikesh::*` → `Baslash::*`)

| File | Notes |
|---|---|
| `lib/baslash/builder.rb` | Public DSL surface; rename only, contents unchanged in spirit |
| `lib/baslash/reline_dialogs.rb` | Drop `run_chrome_tick`, drop `\e7/\e8`; keep `slash_menu_dialog_proc`, `ghost_text_dialog_proc`, `periodic_tick_proc` (delegates to `TitleBar.tick`), `apply_command` |
| `lib/baslash/slash_registry.rb` | Unchanged |
| `lib/baslash/slash_dispatcher.rb` | Unchanged |
| `lib/baslash/handler_ractor.rb` | Unchanged |
| `lib/baslash/context.rb` | Unchanged |
| `lib/baslash/main_ctx.rb` | Unchanged |
| `lib/baslash/ctx_proxy.rb` | Unchanged |
| `lib/baslash/shareable_ref.rb` | Unchanged |
| `lib/baslash/transcript.rb` | Unchanged |
| `lib/baslash/default_commands.rb` | Unchanged in spirit; references updated |
| `lib/baslash/debug_commands.rb` | Unchanged in spirit; references updated |
| `lib/baslash/debug_endpoint.rb` | Unchanged |

### 6.4 Builder DSL surface (preserved, with cleanups)

The example shells call:

```ruby
Baslash.run do |shell|
  shell.header_lines [...]              # boot banner
  shell.shortcuts_hint "..."             # shown once at boot, becomes scrollback
  shell.info_bar { |ctx| [...] }         # rendered into TITLE BAR (was footer row 0)
  shell.status_rows { |ctx| [...] }      # rendered into TITLE BAR (was footer row 1)
  shell.slash :pwd, "Print cwd" do ...
  shell.on_submit do |line, ctx| ... end
end
```

Cleanups (breaking, OK per author; in scope of this spec):

- `header_config` consolidated into `header_lines` (no two-source confusion);
  if `header_config` carries fields `header_lines` does not currently model,
  the new unified API absorbs them
- `evaluate_info_bar(main_ctx)` becomes private; `info_bar` accepts a proc
  that returns the title-bar text fragments (was: footer row 0 segments)
- `evaluate_status_rows(main_ctx)` likewise becomes private; `status_rows`
  proc returns the title-bar context fragments

Out of scope of this spec (revisit later if real friction shows up):

- `shareable_ref` ergonomics
- Slash dispatcher result handling beyond what current contract provides

## 7. TitleBar API

```ruby
module Baslash
  module TitleBar
    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
    TICK_INTERVAL_MS = 200

    def self.set(text)
      $stdout.print("\e]0;#{text.gsub(/[\a\e]/, '')}\a")
      $stdout.flush
    end

    def self.restore
      $stdout.print("\e]0;\a")
      $stdout.flush
    end

    # Called from Reline.periodic_tick. `phase` is :ready or :working;
    # `ctx_text` is the result of merging info_bar + status_rows for display.
    def self.tick(phase:, ctx_text:)
      glyph = phase == :working ? next_spinner_frame : "✻"
      set("#{glyph} #{ctx_text}")
    end

    def self.next_spinner_frame
      @frame ||= 0
      f = SPINNER_FRAMES[@frame % SPINNER_FRAMES.size]
      @frame += 1
      f
    end
  end
end
```

Caveats documented inline:

- tmux: requires `set-window-option allow-rename on` for title to pass
  through. Documented in README.
- Some old terminals strip non-ASCII from titles; spinner glyph degrades to
  `*` if needed (configurable).

## 8. Migration strategy

The rename + pivot is a single coordinated change. No "old + new in parallel"
period — the `cclikesh` gem name + `lib/cclikesh/` tree is replaced wholesale
by `baslash` gem name + `lib/baslash/` tree. The author confirmed examples
are the only consumers, all in this repo, and breaking changes are fine.

**Phasing within the implementation plan (to be authored by `writing-plans`):**

1. Stand up `lib/baslash/` as a new tree alongside `lib/cclikesh/`. New tree
   is non-functional initially.
2. Move + rename modules one at a time, top-down (Builder → Slash registry
   → Display → Runner). Each module gets test coverage in `test/baslash/`.
3. Replace curses with `puts` + `TitleBar` in `Display` and `Runner`.
4. Drop `Chrome`, `TerminfoOverlay`, `LayoutDiag` once all callers moved.
5. Update `examples/echo_shell.rb`, `examples/irb_shell/`, `examples/zsh_shell/`
   to call `Baslash.run` instead of `Cclikesh.run`.
6. Delete `lib/cclikesh/` and the `cclikesh` gemspec.
7. Update `cclikesh-debug/` to test `baslash` (rename internal namespace too,
   since the test harness names match the gem under test).
8. Update README + CHANGELOG.

## 9. Testing strategy

- **Unit tests:** Per-module under `test/baslash/`. Same coverage targets as
  current `test/`.
- **TermSim spec coverage:** Reuse `Cclikesh::Debug::TermSim` (rename to
  `Baslash::Debug::TermSim`). Every PTY spec asserts visible row state via
  TermSim, not byte-count.
- **Boot/exit/slash specs:** Existing PTY specs (R1/R2/R3, slash menu, pwd
  output, winsize stale env) get migrated to the new namespace and the new
  visual model. Most assertions become "TermSim shows expected text on
  expected row".
- **Manual real-terminal smoke:** Author runs each example shell on
  ghostty + cmux at session start, exercises slash menu, types long output,
  scrolls back. Documented as a checklist in
  `docs/superpowers/handoff/<date>-baslash-real-tty-checklist.md`.
- **Title bar visibility:** New unit test asserts that `TitleBar.set("foo")`
  emits `\e]0;foo\a`. New PTY spec asserts that the captured byte stream
  contains the expected title sequence after a `/pwd`.

## 10. Open risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| tmux/screen strips OSC 0/2 by default | Medium | Document `allow-rename on` requirement in README; degrade gracefully if title set is silently dropped (no on-screen consequence) |
| Reline 0.6 has a bug we trigger when no curses owns the screen | Low-medium | Migrate one example shell first as a smoke; if Reline needs a tweak, bound it in a single integration shim |
| Spinner update at 200 ms causes title-bar flicker on some terminals | Low | Reduce to 500 ms or make configurable per-shell; OSC writes themselves don't flicker, only some compositors do |
| `puts` on Ractor message receipt races with Reline's screen ownership | Medium | Existing `apply_command` already serializes via `RelineDialogs.drain_main_mailbox` from the periodic_tick — same pattern keeps working; verify in PTY spec |
| Multi-line command echo from past inputs scrolls off in middle of long output | Low | Acceptable v1 behavior — user can scroll back natively to see the full sequence |

## 11. Out of scope (explicit)

The following are NOT part of this spec; they belong to a future v2 or a
separate spec:

- Mouse handling (wheel scroll redirect, click copy, OSC 52 clipboard)
- Animated dialog UIs (e.g., live-updating spinner in body, not just title)
- Color theme support (palette swap, light/dark)
- Windows Terminal / cmd.exe / PowerShell support
- Linux non-xterm console (Linux framebuffer console, busybox tty)
- File tail / log live-update view
- Multi-pane / split-screen (one shell, two areas)

## 12. Acceptance

A subsequent implementation plan will be considered acceptance-ready when:

1. All current passing tests in root and `cclikesh-debug` pass under the new
   `baslash` namespace.
2. R1/R2/R3 PTY specs (renamed) pass with TermSim-rendered assertions.
3. Author runs each example shell on ghostty + cmux for at least 100 lines
   of body output, scrolls back successfully to the boot banner, and reports
   no visible artifacts.
4. The `cclikesh` namespace and `Curses` dependency are absent from
   `lib/baslash/` and the gemspec.
5. `docs/superpowers/handoff/<date>-baslash-v1-shipped.md` exists with the
   real-TTY checklist results.
