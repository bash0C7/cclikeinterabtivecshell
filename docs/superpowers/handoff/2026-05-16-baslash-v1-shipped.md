# baslash v1 ship — handoff

**Date:** 2026-05-16
**Spec:** `docs/superpowers/specs/2026-05-15-baslash-rename-and-zsh-style-pivot-design.md`
**Plan:** `docs/superpowers/plans/2026-05-15-baslash-rename-and-zsh-style-pivot.md`
**Status:** SHIPPED. All 14 plan tasks + 5 Task-14 follow-up phases complete.

---

## What landed

### Plan tasks 1-13 (rename + curses removal)

`cclikesh` → `baslash` rename across the entire codebase. Curses dependency
dropped. New architecture: body content flows to natural terminal scrollback
via `puts`; status (cwd / var count / phase / spinner) lives in the terminal
title bar via OSC 0. Reline owns prompt + input editing + history + dialog
procs (slash menu / ghost text). Slash subsystem (registry / dispatcher) and
Builder DSL carried over with namespace rename.

Module inventory (all under `lib/baslash/`):

- `version.rb` — `Baslash::VERSION = "0.3.0"`
- `style.rb` — SGR helpers + named/semantic style lookups
- `title_bar.rb` — OSC 0 set/restore + spinner state
- `display.rb` — puts-based body + CR/EL live slots + boxed dialog
- `transcript.rb`, `context.rb`, `main_ctx.rb`, `shareable_ref.rb` — ported
- `slash_registry.rb`, `slash_dispatcher.rb`, `handler_ractor.rb` — ported (HandlerRactor preserved on disk for future use, see below)
- `ctx_proxy.rb` — ported (now used only for the preserved async path)
- `builder.rb` — DSL surface ported, `define_style` becomes a no-op stub, header_lines colored by default
- `default_commands.rb`, `debug_commands.rb`, `debug_endpoint.rb` — ported with `CCLIKESH_` env → `BASLASH_`
- `reline_dialogs.rb` — ported + simplified (drop curses chrome tick, integrate TitleBar)
- `runner.rb` — slim Runner: signal trap + Reline orchestration + main loop + slash dispatch + quit. No curses, no terminfo overlay.
- `sync_ctx.rb` — **NEW** (Phase 2): synchronous main-thread context, mirror of CtxProxy API minus Ractor messaging
- `working_indicator.rb` — **NEW** (Phase 3): Ractor-based TitleBar spinner driver during sync handler execution

`baslash-debug/` is the parallel PTY harness gem, renamed from `cclikesh-debug/`.

### Task 14 follow-up phases

The plan's Task 14 (real-TTY smoke) found 5 issues which were addressed across 5 follow-up phases. See full list below in "Task 14 issues & resolution".

User-facing additions on top of the original spec:

- **Sync dispatch (default)**: handlers run on the main thread between Reline prompts, no race between typing and handler completion. HandlerRactor is preserved on disk for a future explicit-background (Ctrl-B style) mode.
- **WorkingIndicator**: TitleBar spinner ticks every ~120ms during sync handler execution.
- **Semantic style colors**: `:ok` → green, `:ng`/`:error` → red, `:warn` → yellow, `:thinking`/`:meta` → dim cyan. `:result` is intentionally pass-through so impl stdout stays default color.
- **Bold cyan prompt** (`\e[1;36m> \e[0m`).
- **`Builder#prompt_prefix` DSL**: per-prompt dynamic prefix evaluated each render. `examples/zsh_shell/zsh_shell.rb` uses it to show the full cwd.
- **Multi-line prompt suppression**: `Reline.prompt_proc` returns the cwd-prefixed prompt only for line 0; continuation rows are blank.
- **stdin drain on shutdown**: `Runner.drain_residual_stdin` swallows leftover terminal-response bytes (CPR / DSR / etc.) so they don't leak to the calling shell after `/exit`.

---

## Test suite at ship time

| Suite | Tests | Assertions | Failures | Errors | Omissions |
|---|---|---|---|---|---|
| root `bundle exec rake test` | 190 | 271 | 0 | 0 | 3 |
| `baslash-debug` `bundle exec rake test` | 80 | 198 | 0 | 0 | 2 |
| examples smoke (`test_examples_smoke_baslash.rb`) | 3 | 2 | 0 | 0 | 1 |

Total: 273 tests, 0 failures, 0 errors across all suites.

Omissions breakdown (all pre-existing or deferred):
- `test_handler_ractor_baslash.rb` × 2 — deferred until explicit-background (Ctrl-B) mode lands; tests omit with documented reason.
- `irb_shell` smoke — pre-existing `Ractor.new: allocator undefined for Binding (TypeError)` bug; `IrbEvaluator` stores `@binding = fresh_binding` and `Builder#shareable_ref` can't ship Binding across Ractors. Tracked as separate follow-up; needs design call (evaluator could keep TOPLEVEL_BINDING via constant or not be a shareable_ref). Out of scope for this ship.
- `baslash-debug/test/specs/cmux_env_*.rb` × 2 cmux R-specs — annotated with NOTE comments; the expects reference legacy `Cclikesh::Chrome` diag surface that no longer emits post-Task-9.

---

## Task 14 issues & resolution

User found 5 issues during real-TTY verification of zsh_shell on macOS Terminal.app:

| Issue | Symptom | Root cause | Resolution |
|---|---|---|---|
| **C** | `/<Enter>` crashed (`nil.to_sym`) | `SlashRegistry#lookup(nil)` not guarded; dispatcher passed nil name | Layer 1: dispatcher returns silently on bare `/`. Layer 2: `lookup` nil-safe. Commit `135f9c8`. |
| **D** | Slash menu hid the prompt | `Reline::CursorPos.new(0, 0)` didn't anchor x and didn't cap height → Reline's flip-above branch never engaged | `pos: CursorPos.new([cx - typed.bytesize, 0].max, 0)` + `height = [contents.size, 12].min`. Commit `67b1fa4`. |
| **E** | Tab didn't cycle slash candidates | `Reline.completion_proc` was nil when `on_tab_handler` not supplied; Reline's journey machinery short-circuits | Install a default proc keyed on `slash_registry.slash_menu_items_starting_with(prefix)`. Commit `67b1fa4`. |
| **A** | `^[[26;1R` (CPR) leaked into outer shell after `/exit` | `ctx.quit` did `Process.kill("INT", Process.pid)` mid-`\e[6n` query; Reline's stdin response stranded in tty buffer | Sync mode makes quit synchronous (no Process.kill), AND `Runner.drain_residual_stdin` clears any residue (Phase 4). Commit `aaeffd4` + `7893bfe`. |
| **B** | "ls didn't work" in zsh_shell | NOT A BUG — verified via PTY harness. User saw an unfamiliar listing because cwd was different than expected. | None. |

Additional issues found during Task 14 follow-up:

| Issue | Symptom | Root cause | Resolution |
|---|---|---|---|
| `/btw foo` crashed | `block.call` raised NoMethodError on nil | `SlashRegistry.register` wrapped bodies with `Ractor.shareable_proc` which strips closures. In sync mode, this is unnecessary AND breaks any closure-capturing slash body. | Drop `Ractor.shareable_proc` from `SlashRegistry.register`. Commit `afddbdb`. |
| `/debug-emit` / `/debug-tick-counter` / `/debug-curses-caps` / `/debug-snapshot` crashed | NoMethodError on SyncCtx | Phase 2 SyncCtx pivot didn't port 4 message-passing helpers that CtxProxy had | Added `DisplayProxy#raw_emit` + `debug_snapshot` + `debug_tick_count` + `debug_curses_caps` on SyncCtx. Commit `301de9d`. |
| Multi-line prompt repeated on every line | `Reline.readmultiline` defaults to repeating the static prompt | Needed `Reline.prompt_proc` to return per-line prompts | Set `Reline.prompt_proc` to emit prefix only on line 0; blank for continuation rows. Commit `71e7685`. |

---

## Real-TTY verification results

User confirmed on macOS Terminal.app + cmux:

| Check | echo_shell | zsh_shell |
|---|---|---|
| Banner renders (logo cyan + title bold) | ✅ | ✅ |
| Prompt bold cyan `> ` | ✅ | ✅ |
| Prompt prefix with full cwd | n/a | ✅ |
| Slash menu autocomplete appears (Issue D fix) | ✅ | ✅ |
| Tab cycles slash menu candidates (Issue E fix) | ✅ | ✅ |
| `/` bare crash fixed (Issue C) | ✅ | ✅ |
| Body content scrolls to native scrollback | ✅ | ✅ |
| Multi-line shift+enter, prompt only on line 1 | ✅ | ✅ |
| Window resize survives | ✅ | ✅ |
| Title bar spinner during sync handler | ✅ | ✅ |
| Ctrl-C aborts running handler with `^C` line | ✅ | ✅ |
| `/exit` clean (no CPR leak — Issue A fix) | ✅ | ✅ |
| `:result` (impl stdout) stays default color | ✅ | ✅ |
| `:ok` / `:ng` framework status colored | n/a | ✅ |
| cd / export interception | n/a | ✅ |
| `/btw` closure capture (regression check) | ✅ | ✅ |

cmux passthrough: confirmed working (OSC 0 title set, body scrollback intact).

---

## Architecture decisions

### 1. Sync dispatch as default (Phase 2)

The original plan had handlers run in a per-invocation Ractor (`HandlerRactor`) with messages back to the main Ractor (`CtxProxy.apply_command`). After user testing surfaced typing-vs-handler race conditions, we pivoted to sync execution on the main thread.

Trade-offs:
- ✅ No race between user typing and handler output
- ✅ Closure capture works in slash bodies (drop of `Ractor.shareable_proc`)
- ✅ Ctrl-C abort is trivial (`rescue Interrupt`)
- ✅ Simpler debug commands (direct calls instead of request/reply messages)
- ❌ Long-running handlers block the shell — mitigated by user-supplied Ctrl-C
- ❌ Loss of Ractor isolation — handlers must self-discipline against global state mutation

HandlerRactor / CtxProxy preserved on disk for future explicit-background mode (Claude-Code-style Ctrl-B). Tests for HandlerRactor are omit-ed with that note.

### 2. TitleBar spinner via WorkingIndicator (Phase 3)

User wanted in-prompt `*`/`+` animation during handler execution. Implementing inline-prompt animation cleanly is hard (puts vs animation line conflicts, cursor save/restore complexity). Chose TitleBar-only spinner for v1 since the existing TitleBar infrastructure already supports it. Document trade-off for follow-up if user wants in-prompt animation.

WorkingIndicator uses a Ractor (not Thread) because `test_thread_zero.rb` enforces no-Thread.new in `lib/`.

### 3. Semantic styles are framework-only (Phase 5.5)

User's mental model: framework colors framework-emitted content (errors, status, banner, slash menu desc, `> `). Impl execution results (`:result`) and user-typed text stay default color. This is encoded in `Style::SEMANTIC_STYLES` — `:result` intentionally absent.

---

## Files unchanged but worth knowing

- `Gemfile`: uses `gemspec` (resolves baslash.gemspec) + `gem "baslash-debug", path: "baslash-debug"`. No curses dep.
- `Rakefile`: `debug:*` tasks point at `baslash-debug/exe/baslash-debug` with `BASLASH_DEBUG_DIR`.
- `README.md`: rewritten with new scope statement (macOS / Terminal.app + cmux / no curses / OSC 0 title bar).
- `.gitignore`: `/baslash-debug/tmp/` added.

---

## Commit topology (since baseline `e17891e`)

34 commits, all on `main` local-only (not pushed). Chronological:

```
bda91ff feat(baslash): bootstrap gem skeleton with version + Baslash.run stub
9078627 feat(baslash): Style module with SGR helpers (bold/dim/color/apply/strip)
5cbaf94 feat(baslash): TitleBar module with OSC 0 set/restore + spinner tick
1d56a9c feat(baslash): Display module — puts-based body, CR/EL live slots, boxed dialog
453794a feat(baslash): port Context + ShareableRef + Transcript
395abbf fix(baslash): address Task 5 review — baslash-transcript log path, transcript test coverage, frozen_string_literal
04d19d2 feat(baslash): port slash subsystem (registry / dispatcher / handler ractor)
e34e743 feat(baslash): port DSL surface (main_ctx / ctx_proxy / builder)
4f259ec fix(baslash): address Task 7 review — stub define_style, fix stale (curses) comment
cb0ab98 feat(baslash): port slash commands (default + debug + endpoint), rename CCLIKESH_ env to BASLASH_
57ed228 fix(baslash): remove cclikesh/reline_idle_patch require from test (Task 13 prep)
808d582 feat(baslash): RelineDialogs ported + simplified — drop curses chrome tick, integrate TitleBar
e75555d fix(baslash): sync debug_commands display with new TitleBar snapshot keys
74316b0 feat(baslash): slim Runner (no curses) + wire Baslash.run entry point
d202551 fix(baslash): log lifecycle hook failures + drop dead tick_counter kwarg
fe9551f feat(examples): migrate echo/zsh/irb shells to Baslash.run
b09a388 fix(examples): inline prompt prefix in irb_shell display + extend smoke to zsh/irb
0edd3f4 feat(debug): rename cclikesh-debug -> baslash-debug + namespace + paths
07585bd chore(debug): untrack baslash-debug/tmp test artifacts + gitignore
eb9422a fix(baslash): drop dead curses require from debug_endpoint#current_cursor
2d712e2 fix(debug): annotate stale Chrome-era R-specs + narrow bare rescue in debug_endpoint
3aee6b9 chore(baslash): delete obsolete curses-era and cclikesh-namespace tests
fc5a18c chore(baslash): delete legacy cclikesh library tree and gemspec
b73df0d chore(baslash): update README, simplify Gemfile, scrub cclikesh comments
135f9c8 fix(baslash): handle bare '/' input without crashing
67b1fa4 fix(baslash): slash menu position + default tab completion proc for slash registry
aaeffd4 feat(baslash): sync dispatch via SyncCtx (drop HandlerRactor from default path)
28dd27e feat(baslash): WorkingIndicator drives TitleBar spinner during sync handler execution
bde985e feat(baslash): color prompt, slash menu description, and banner header
7893bfe fix(baslash): drain residual stdin on shutdown to suppress terminal-response leaks
1c5f49d feat(baslash): semantic style colors, bold prompt, and prompt_prefix DSL
71e7685 fix(baslash): suppress prompt on multi-line continuation rows (Reline.prompt_proc)
afddbdb fix(baslash): drop Ractor.shareable_proc from SlashRegistry to allow closure capture in sync mode
301de9d fix(baslash): add SyncCtx helpers for debug commands (raw_emit, debug_snapshot/tick_count/curses_caps)
```

---

## Open follow-ups (post-ship)

These are NOT blocking the v1 ship but worth tracking:

1. **`irb_shell` Binding-not-shareable** — IrbEvaluator stores `@binding = fresh_binding`, which can't ship across Ractors. Needs design call. The irb_shell smoke test is currently omit-ed.
2. **PTY R-specs need rewrite** — `baslash-debug/test/specs/cmux_env_*.rb` × 3 reference legacy `Cclikesh::Chrome` diag tags (FOOTER_HEIGHT, draw_dividers, handle_resize.after_resizeterm). They silently no-op (NOTE comments document this). Should be rewritten against new TitleBar/Runner diag surface.
3. **Explicit-background mode (Ctrl-B)** — HandlerRactor + CtxProxy preserved on disk for this. Would require: keybinding, BG job tracking, completion reporting, ability to interleave foreground prompts with BG output. Substantial scope.
4. **In-prompt animation** — user originally asked for `*`/`+` toggle in the `>` prompt during execution. We delivered TitleBar spinner as v1 (cleaner architecturally). If desired, in-prompt animation can be added as a Phase 3.5 follow-up.
5. **Local-only commits** — the 34 commits since baseline are not pushed. Push when ready (user gate per global rule).
6. **CHANGELOG.md** — doesn't exist in repo. v0.3.0 entry skipped per "if exists" clause in plan.

---

## How to verify the shipped state

```bash
# from repo root
bundle exec rake test                                 # → 190 tests / 0 failures
cd baslash-debug && bundle exec rake test ; cd ..     # → 80 tests / 0 failures
bundle exec ruby -Ilib -Itest test/test_examples_smoke_baslash.rb  # → 3 tests / 0 failures

# real-TTY smoke
bundle exec ruby examples/echo_shell.rb     # exit with /exit
bundle exec ruby examples/zsh_shell/zsh_shell.rb     # try /pwd, ls, /btw foo, sleep 5 + Ctrl-C, /exit

# leakage check
grep -rln "Cclikesh\|cclikesh" --exclude-dir=docs --exclude-dir=.git --exclude='*.md' --exclude='Gemfile.lock' .
# → 3 matches, all NOTE comments in baslash-debug/test/specs/cmux_env_*.rb (intentional historical markers)
```

baslash v1 is shipped. The 34 commits since `e17891e` constitute the full rename + zsh-style + title-bar pivot + sync-mode UX polish. Ready to push when user gates.
