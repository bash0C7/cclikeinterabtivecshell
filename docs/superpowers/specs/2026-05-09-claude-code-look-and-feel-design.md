# cclikesh — Claude Code Look & Feel (Full Fidelity) Design

**Date:** 2026-05-09
**Status:** approved (scope: full Claude Code parity, no MVP simplification)
**Predecessor:** `2026-05-09-cclikesh-design.md` (foundation through Plan 6)

---

## 1. Goal

Make the cclikesh framework render and behave **exactly like Claude Code's terminal UI**. Every visible region, every interaction primitive, every input mode that real Claude Code exposes must be available as a framework primitive. The `examples/irb_shell/irb_shell.rb` example uses the subset relevant to an irb experience. No "MVP simplification" — every feature listed in this spec is mandatory.

**Reference:** Claude Code v2.1.138 fullscreen rendering mode (https://code.claude.com/docs/en/fullscreen) + interactive-mode reference (https://code.claude.com/docs/en/interactive-mode).

---

## 2. Target screen layout

```
┌─────────────────────────────────────────────────────┐
│ ✻  cclikesh v0.1.0                                  │ HEADER REGION
│    Ruby 3.x · ~/dev/.../cclikeinterabtivecshell     │ (auto height,
│    irb on cclikesh · /q to exit                     │  fixed top)
│                                                     │
│ ▌ /reset                                            │ HISTORY REGION
│  └ session reset                                    │ (scrollable,
│                                                     │  alt-screen,
│ irb(main)> x = 41                                   │  virtual buffer
│ => 41                                               │  + viewport,
│                                                     │  auto-follow)
│ irb(main)> x.to_                                    │
│           ┌─────────────────┐                       │
│           │ to_s            │ ← popup completion    │
│           │ to_i            │                       │
│           │ to_f            │                       │
│           └─────────────────┘                       │
│                                                     │
│ ❭ ▏                                                 │ INPUT REGION
│ ✻ Roosting · 5s · ↓ 1.2k · main · 21:36 · 0 tokens  │ FOOTER REGION
│   ░░░░░░░░░░░░ 0% · 26/05/10 02:30                  │ (multi-row,
│   ░░░░░░░░░░░░ 23% · 26/05/16 03:00                 │  fixed bottom)
└─────────────────────────────────────────────────────┘
```

Every region paints independently. Alt-screen buffer is used so the host terminal scrollback stays clean.

---

## 3. Architecture

### 3.1 Rendering surface

- **Alt-screen entry** at Runner start: write `\e[?1049h\e[?25h` (alt-screen on, cursor visible)
- **Alt-screen exit** at Runner shutdown: write `\e[?1049l\e[?25h`
- 4 named **Regions** (`Cclikesh::Region`): each owns `(start_row, height, content)` and exposes `paint(lines)` which positions the cursor with `\e[<row>;<col>H` and writes
- A **Screen** singleton owns terminal dimensions, region layout (header height + history viewport height + input height + footer height = total rows), and dispatches SIGWINCH-driven recompute + full repaint
- The **Renderer** is now `Region`-aware. RenderThread tick: drain dirty Regions, paint visible region only

### 3.2 History as virtual buffer + viewport

- `Cclikesh::Viewport` holds an append-only `Array<Entry>` (an Entry = one rendered block: text line, slash tag + result, live slot, dialog box, etc.)
- Viewport tracks `top_index` (first visible entry) and `auto_follow` flag
- Append normally pushes + bumps top to follow latest
- PgUp / PgDn / Ctrl+Home / Ctrl+End navigate top_index, toggle auto_follow
- Memory is flat: only visible entries are converted to ANSI lines per paint

### 3.3 Input region (Reline integration)

- Reline still drives line editing, but **Reline.output is redirected** to an `InputIO` adapter that absorbs Reline's writes and writes them positioned to the input region (last-2 row, since footer = last-1+ rows)
- Reline `prompt_proc` is set so multi-line prompts (`\<Enter>`, `Shift+Enter`, `Ctrl+J`) expand the input region height up to `input_max_rows` (default 5)
- Vim mode is enabled via `Reline.vi_editing_mode` when builder config sets `editor_mode: :vim`

### 3.4 Process model

The DRb impl ↔ F split established in the foundation **stays unchanged**. Every new primitive in this spec is implementation inside F (the front-end terminal process). impl-facing handlers continue to go through `HandlerRegistry` over DRb. The `Display`, `Dialog`, `Viewport`, `Screen`, `Region` classes are F-internal — never marshalled, never DRb-fronted.

---

## 4. Sub-projects (each → its own implementation plan)

The work decomposes into 5 sub-projects. Each is independently shippable; downstream sub-projects assume the foundation but earlier ones don't depend on later ones.

### Sub-project A: Renderer foundation (Plan 7)
Alt-screen entry/exit, 4-region paint, viewport with virtual buffer, SIGWINCH resize, basic auto-follow, Ctrl+L double-press redraw. Replaces the existing inline-stdout renderer.

### Sub-project B: Visual polish (Plan 8)
Header region DSL, footer multi-row + bar primitive + linked-segment primitive (PR-status colored underline pattern), slash command tag rendering with multi-state (pending/running/done/error) + `└` indent on result.

### Sub-project C: Mouse interaction (Plan 9)
Mouse capture (`\e[?1003h\e[?1006h`), parse mouse events, click-to-position-cursor in input, click-to-expand collapsed entries (each entry has `expand_state`), click-on-URL/file-path opens system handler, text selection via mouse with copy-on-release to clipboard via OSC 52, `CLAUDE_CODE_DISABLE_MOUSE` equivalent opt-out env.

### Sub-project D: Slash menu + popup picker (Plan 10)
Type `/` → popup picker showing slash command names + descriptions, arrow keys navigate, Enter commits, Esc cancels. Built atop existing `slash_names_starting_with`. Slash commands gain a `description` field.

### Sub-project E: Input modes & prompt suggestion (Plan 11)
- `@<path>` → file path autocomplete with picker (Glob-driven)
- `!<cmd>` → shell mode: command echoes into history, output captured to history, `Ctrl+B` backgrounds, exit on Esc/Ctrl+U
- Multi-line input via `\<Enter>` / `Shift+Enter` / `Ctrl+J` (Reline native)
- Prompt suggestion: grayed-out hint after cursor, Tab/Right accepts. DSL `shell.prompt_suggestion { |ctx| ... }`

### Sub-project F: Reverse search + Vim mode (Plan 12)
- `Ctrl+R` reverse history search popup with type-to-filter, `Ctrl+R` cycle, `Ctrl+S` scope cycle, `Tab`/`Esc` accept, `Enter` accept-and-execute
- Vim mode toggle (Reline native)
- Per-cwd history persistence (`~/.cclikesh/history/<cwd-hash>`)

### Sub-project G: Transcript mode + /focus (Plan 13)
- `Ctrl+O` toggles transcript viewer: less-style nav (`/`, `n`, `N`, `j`/`k`, `g`/`G`, `Ctrl+u`/`Ctrl+d`, `Space`/`b`, `q`)
- `[` writes full conversation to native scrollback via leaving alt-screen briefly
- `v` writes to temp file and opens `$VISUAL`/`$EDITOR`
- `/focus` slash command toggles focus mode (only show last prompt + collapsed tool-call summary + final response). State persists in `~/.cclikesh/config.json`

### Sub-project H: Side question /btw (Plan 14)
- Built-in `/btw <question>` slash command opens an ephemeral overlay showing answer (handler-supplied), doesn't enter history, dismissed with Space/Enter/Esc
- DSL: `shell.btw { |question, ctx| ... }` returns answer string

### Sub-project I: irb completion enhancement (Plan 15)
- Replace `IrbCompleter`'s prefix matcher with `IRB::RegexpCompletor` (stdlib, no eval)
- Optional `IRB::TypeCompletor` integration when `irb` gem ≥ 1.10 + `prism` available
- **Inline popup display** of candidates: when >1 candidate, render a popup box near cursor inside history region (anchored to current line), use arrow keys to navigate

Roll-out order: A → B → C → D → E → F → G → H → I. A is foundation for all; the rest are mostly independent but C depends on A's region addressing, G depends on A's alt-screen control, I depends on D's popup primitive.

---

## 5. Component-level design

### 5.1 Sub-project A: Renderer foundation

**New files:**
- `lib/cclikesh/screen.rb` — terminal size, alt-screen enter/leave, SIGWINCH trap, region layout calc
- `lib/cclikesh/region.rb` — `Region.new(name, screen)` with `start_row=`, `height=`, `paint(lines)` (`\e[<row>;1H\e[2K<line>` per line)
- `lib/cclikesh/viewport.rb` — virtual buffer (`entries: Array<Entry>`), `top_index`, `auto_follow`, `visible_lines(height)`, `scroll_up(n)`, `scroll_down(n)`, `pgup`, `pgdn`, `home`, `end_`
- `lib/cclikesh/entry.rb` — base class for renderable entries: `Entry::Text`, `Entry::SlashTag`, `Entry::LiveSlot`, `Entry::Dialog`, `Entry::Popup` (opaque to viewport, each knows its own line count + `to_lines`)
- `lib/cclikesh/input_io.rb` — adapter passed to `Reline.output=`. Buffers Reline writes, repaints input region on flush

**Modified files:**
- `lib/cclikesh/runner.rb` — `Screen.enter_alt`/`Screen.leave_alt` bracket the main loop, install SIGWINCH trap, set `Reline.output = InputIO.new(input_region)`
- `lib/cclikesh/render_thread.rb` — tick body now drains dirty regions and calls `region.paint(lines)`. Dirty signal comes from `Display.append`, viewport scroll, footer/header changes
- `lib/cclikesh/display.rb` — `append` pushes an `Entry::Text` onto viewport, marks history region dirty
- `lib/cclikesh/dialog.rb` — `show` pushes `Entry::Dialog` onto viewport (replaces ASCII-box-as-text MVP)
- `lib/cclikesh/live_slot.rb` — backed by `Entry::LiveSlot` whose state-machine is in viewport entries

**DSL additions:**
```ruby
shell.input_max_rows 5             # default cap on multi-line input height
shell.editor_mode :vim             # or :emacs (default)
```

**Acceptance:**
- Alt-screen entered on Runner start, left on shutdown, terminal scrollback unaffected
- Resize the terminal mid-session: regions recomputed, repaint clean
- 1000+ history entries: memory usage flat (only visible entries rendered per tick)
- Existing 194 tests + new ~30 unit tests + 2 PTY E2E (alt-screen toggle, viewport scroll) pass

### 5.2 Sub-project B: Visual polish

**Header (`lib/cclikesh/header.rb`):**
```ruby
shell.header do |h|
  h.logo  "✻"                                 # 1-char glyph
  h.title "cclikesh"
  h.version "v0.1.0"
  h.subtitle "Ruby #{RUBY_VERSION} · #{Dir.pwd}"
  h.note   "irb on cclikesh · /q to exit"
end
```
Header is paint-once-then-static. `ctx.header.refresh` repaints (e.g. after `/clear`).

**Footer multi-row (`lib/cclikesh/footer.rb` — extends current InfoBar):**
- Existing `info(:name) { ... }` registers a segment on row 0 (line 1) — backward compatible
- New: `shell.status_row(:usage, order: 1) { |row, ctx| ... }` registers another row
- Row API:
  - `row.text(str, style: :dim)` — plain segment
  - `row.bar(percent: 0..100, width: 12, filled: "█", empty: "░", style: :cyan)`
  - `row.link(text:, url:, state: :green|:yellow|:red|:gray|:purple)` — text with colored underline (PR-style); click handler dispatched via mouse layer
  - `row.icon(":symbol")` — pre-baked Unicode glyph
  - `row.spinner` — current spinner frame

Footer height = number of registered rows + 1 (line 0 = info segments + spinner).

**Slash command tag rendering (`lib/cclikesh/slash_render.rb`):**
- `HandlerRegistry#dispatch_slash` wraps handler invocation
- Before handler runs: push `Entry::SlashTag.new(name, args, state: :running)` to viewport
- During handler: any `ctx.display.append` is captured into the SlashTag's `result_lines`
- After handler: SlashTag transitions to `state: :done` (or `:error` on rescue, with `error_msg`)
- Rendering:
  - `▌ /<name> <args>` on tag line, grey 245 background `\e[48;5;245m\e[97m … \e[0m`
  - Each `result_line` rendered as `  └ <line>` (only first), subsequent lines `    <line>`
  - Pending state: prefix with spinner frame `\e[36m✻\e[0m`
  - Error state: `└ \e[31m<error>\e[0m`
- DSL: `shell.slash_render :tag` (default) or `:plain` (legacy). Per-slash override via `shell.slash(:reset, render: :plain) { ... }`

**Acceptance:** PTY E2E shows grey-tag rendering for `/reset`, multi-state transitions work, footer multi-row paints with bar primitive, header paints on start.

### 5.3 Sub-project C: Mouse interaction

**New file `lib/cclikesh/mouse.rb`:**
- Enable: `\e[?1000h\e[?1003h\e[?1006h` (button + motion + SGR encoding)
- Disable on shutdown
- `Mouse.parse(escape_sequence)` → `MouseEvent(button:, x:, y:, type: :press|:release|:motion|:wheel_up|:wheel_down)`
- Stdin reader thread reads raw bytes (raw mode); when `\e[<` detected, parse mouse event, dispatch to `MouseRouter`
- `MouseRouter` maps `(x, y)` to `(region, entry, hit_target)`:
  - history region click on `Entry` with `expandable?` → toggle `expand_state`
  - history click on URL/path detected via OSC 8 hyperlink ranges → fork system handler (`open` on macOS, `xdg-open` on Linux)
  - input region click → set Reline cursor to char position
  - footer link click → dispatch `link.on_click` handler

**Text selection:**
- Click+drag tracked, painted with reverse-video on overlapping entries
- Release: copy selected text to clipboard via OSC 52 (`\e]52;c;<base64>\a`) — works over SSH/tmux

**Opt-out:** `CCLIKESH_DISABLE_MOUSE=1` env var skips enabling mouse capture.

**DSL:** none required for builders. URL detection is automatic via OSC 8 sequences in `Entry::Text`.

**Acceptance:** PTY E2E injecting mouse escape sequences validates click-to-expand, click-to-position. Text selection unit-tested via mouse event sequences.

### 5.4 Sub-project D: Slash menu popup

**New file `lib/cclikesh/popup.rb`:**
- `Popup.new(items:, anchor:, on_select:)` — renders box with bordered list near anchor
- Arrow up/down navigates highlight, Enter calls `on_select.call(item)`, Esc closes

**Slash command DSL extension:**
```ruby
shell.slash(:reset, description: "reset irb session") { |args, ctx| ... }
```
`description` shown in popup.

**Trigger:**
- InputThread monitors Reline buffer; when buffer is exactly `/` or `/<prefix>`, open Popup with matching slash names + descriptions
- Popup is an `Entry::Popup` pushed to viewport (rendered above input area)

**Acceptance:** PTY E2E typing `/r` shows popup with `/reset`, arrow + Enter executes.

### 5.5 Sub-project E: Input modes & prompt suggestion

**`@<path>` mention:**
- InputThread detects `@` at start or after space; opens file picker popup driven by `Dir.glob`
- Selected path gets inserted as `@<relative-path>` token
- Handler receives the line as-is — handler interprets `@path` tokens

**`!<cmd>` shell mode:**
- Buffer starts with `!` and Enter pressed
- Command rendered as `! $ <cmd>` history entry
- Spawn via `Open3.popen3`, output captured into a `Entry::ShellOutput` block, streamed
- `Ctrl+B` backgrounds (move to background-tasks list, output redirected to file)
- Exit shell mode: `Esc`, `Backspace`, or `Ctrl+U` on empty prompt

**Multi-line input:**
- Reline natively supports `\<Enter>`, `Shift+Enter` (terminal-dependent), `Ctrl+J`
- Input region grows up to `input_max_rows`
- Each prompt line gets `❭` indicator, continuation lines indented

**Prompt suggestion:**
- DSL: `shell.prompt_suggestion { |ctx| ... }` returns `String` or `nil`
- Suggestion painted in dim grey after cursor when input is empty
- `Tab` or `Right` accepts (puts string into Reline buffer)
- Disabled by env `CCLIKESH_DISABLE_PROMPT_SUGGESTION=1`

**Acceptance:** PTY E2E for each mode (`@README<Tab>`, `!ls`, prompt suggestion accept, multi-line submit).

### 5.6 Sub-project F: Reverse search + Vim mode

**`Ctrl+R` reverse search:**
- Opens overlay popup: search field at top, matching history entries below
- Type to filter (substring match), `Ctrl+R` cycles older matches, `Ctrl+S` cycles scope (this-session / this-project / all-projects)
- `Tab`/`Esc` accept into input, `Enter` accept-and-execute
- History persistence: `~/.cclikesh/history/<sha1(cwd)>.jsonl`, append on submit, load on start

**Vim mode:**
- DSL: `shell.editor_mode :vim`
- Maps to `Reline.vi_editing_mode = true`
- Plus per-key extensions for our overlays (Esc closes popup, etc.)

**Acceptance:** PTY E2E reverse-search workflow + vim mode insert/normal switching.

### 5.7 Sub-project G: Transcript mode + /focus

**Transcript mode (`Ctrl+O`):**
- Push current viewport state, clear input region, paint header + transcript region (full screen sans header) + nav-help footer
- `j`/`k`/`↑`/`↓` scroll one line, `Ctrl+u`/`Ctrl+d` half-page, `Space`/`b` full-page, `g`/`G` jump
- `/` opens search; `n`/`N` next/prev match; matches highlighted
- `[` writes full conversation to native scrollback (briefly leaves alt-screen, prints, returns)
- `v` writes to `Tempfile.create`, spawns `$VISUAL || $EDITOR || vi`
- `q`/`Esc`/`Ctrl+O` exits back to interactive

**`/focus` slash:**
- Built-in slash command. Toggles `viewport.focus_mode = !focus_mode`
- In focus mode, viewport renders only: most recent prompt + summarized tool-calls (1-line each: `↪ /<name> done`) + final response
- Persisted to `~/.cclikesh/config.json`

**Acceptance:** PTY E2E transcript open/scroll/search/exit + `/focus` toggle behavior.

### 5.8 Sub-project H: /btw side question

- Built-in `/btw <question>` slash
- DSL: `shell.btw { |question, ctx| ... }` returns answer string (handler can be sync or use `ctx.thread { ... }`)
- Renders ephemeral overlay (`Entry::SideQuestion`) — NOT pushed to viewport, painted directly on top of history region
- Dismissed with Space/Enter/Esc; overlay disappears, history region repaints

**Acceptance:** PTY E2E `/btw what is 2+2` → answer overlay appears, Space dismisses without leaving history trace.

### 5.9 Sub-project I: irb completion (RegexpCompletor + popup)

**Replace `examples/irb_shell/irb_completer.rb`:**

```ruby
require "irb/completion"

class IrbCompleter
  def initialize(binding)
    @binding = binding
    @regex = IRB::RegexpCompletor.new
    @type  = try_type_completor
  end

  def candidates(buf, pos)
    pre, target, post = split_at_cursor(buf, pos)
    cands = (@type || @regex).completion_candidates(pre, target, post, bind: @binding)
    cands || []
  end

  private

  def try_type_completor
    require "irb/type_completion/completor"
    IRB::TypeCompletion::Completor.new
  rescue LoadError
    nil
  end

  def split_at_cursor(buf, pos)
    left  = buf[0...pos]
    right = buf[pos..] || ""
    m = left.match(/(?<head>.*?)(?<tgt>[\w:.@$]*)\z/m)
    [m[:head], m[:tgt], right]
  end
end
```

**Inline popup display:**
- When `candidates.size > 1`, push `Entry::Popup` (from sub-project D) onto viewport anchored to current input row
- Single candidate: directly inserted into Reline buffer (no popup)
- TypeCompletor preferred when available (type-aware: `"foo".<Tab>` shows only String methods)

**Acceptance:** PTY E2E `"foo".rev<Tab>` shows `reverse` candidate, `Net::H<Tab>` shows `Net::HTTP*`, multi-candidate triggers popup, single candidate inserts.

---

## 6. DSL surface (full Builder + ctx after all sub-projects)

```ruby
Cclikesh.run do |shell|
  # === foundation (existing) ===
  shell.tick_interval 0.06
  shell.spinner    { |s| s.frames = ...; s.colors = [...]; s.frame_interval = 0.15 }
  shell.spinner_label { |ctx| ctx.state[:phase] == :working ? :auto : nil }
  shell.idle_phrases  ["Roosting", ...]
  shell.idle_phrase_interval 3.0
  shell.define_style :result, fg: :green
  shell.logger     = Logger.new($stderr)
  shell.log_level  = :info
  shell.log_to     "/tmp/cclikesh.log"
  shell.on_start   { |ctx| ... }
  shell.on_quit    { |ctx| ... }
  shell.on_state_change { |key, old, new, ctx| ... }
  shell.before_submit / on_submit / after_submit { |line, ctx| ... }
  shell.before_tab   / on_tab    / after_tab    { |buf, pos, ctx| ... }
  shell.slash(:name, description: "...", render: :tag) { |args, ctx| ... }
  shell.info(:elapsed, order: 10) { |ctx| ... }

  # === sub-project A (renderer foundation) ===
  shell.input_max_rows 5

  # === sub-project B (visual polish) ===
  shell.header do |h|
    h.logo "✻"
    h.title "myshell"
    h.version "v0.1.0"
    h.subtitle "..."
    h.note "..."
  end
  shell.status_row :usage, order: 1 do |row, ctx|
    row.bar percent: ctx.state[:context_pct] || 0, width: 12
    row.text Time.now.strftime("%H:%M")
  end

  # === sub-project E ===
  shell.editor_mode :vim
  shell.prompt_suggestion { |ctx| ctx.state[:last_suggestion] }
  shell.shell_mode_handler { |cmd, ctx| ... }    # custom !cmd handler

  # === sub-project H ===
  shell.btw { |q, ctx| answer_for(q) }
end
```

**ctx additions:**
- `ctx.viewport` — scroll, focus_mode, count
- `ctx.header.refresh`
- `ctx.popup.show(items:, on_select:)` (programmatic popup invocation)
- `ctx.transcript.write_to_scrollback` (programmatic `[` action)
- `ctx.thread { ... }` (run async block; logs error if raises)

---

## 7. Test strategy

### 7.1 Unit tests
- ANSI escape sequences emitted on enter/leave alt-screen, mouse capture, OSC 52
- Region.paint writes to correct row range
- Viewport scroll/PgUp/Home math
- Mouse event parser SGR-encoded sequence
- IrbCompleter delegates to `IRB::RegexpCompletor` (no eval), TypeCompletor preferred when loadable

### 7.2 PTY E2E (`test/test_e2e_pty.rb`)
Each sub-project adds 2-4 PTY tests asserting actual ANSI byte sequences in PTY output. Existing 5 PTY tests must stay green. Total target: ~25 PTY tests after Plan 15.

### 7.3 Regression invariant
Every plan completion: `bundle exec rake test` shows `0 failures, 0 errors`. Plans build cumulatively — Plan 8 still requires 194 + Plan-7-additions tests pass, Plan 9 still requires Plan-8-additions pass, etc.

---

## 8. Roll-out (each line → its own implementation plan)

| Plan | Sub-project | Scope | Est. tasks |
|---|---|---|---|
| 7  | A | Renderer foundation: alt-screen + 4-region + viewport + SIGWINCH + Ctrl+L | ~12 |
| 8  | B | Header + footer multi-row + bar/link primitives + slash tag rendering | ~10 |
| 9  | C | Mouse capture + click-to-expand + click-URL + text selection + OSC 52 | ~9 |
| 10 | D | Slash popup picker + slash description DSL | ~6 |
| 11 | E | `@`/`!`/multi-line/prompt suggestion | ~9 |
| 12 | F | Reverse search + per-cwd history + vim mode | ~7 |
| 13 | G | Transcript mode + `/focus` | ~7 |
| 14 | H | `/btw` side question overlay | ~4 |
| 15 | I | irb completion (RegexpCompletor + TypeCompletor + inline popup) | ~5 |

**Total: 9 plans, ~69 tasks.** Each plan ships independently green.

---

## 9. Acceptance criteria (full spec)

A user running `bundle exec ruby examples/irb_shell/irb_shell.rb` after Plan 15 should observe:

1. Terminal switches to alt-screen, host scrollback unaffected
2. Header banner (logo + title + version + cwd) at top
3. History region auto-scrolls; PgUp pauses auto-follow; Ctrl+End resumes
4. Footer shows spinner + idle phrase + elapsed + token count + multi-row status
5. Type `/r` → popup shows `/reset · reset irb session`, Enter executes, slash tag renders `▌ /reset` + `└ session reset`
6. Type `x = 41<Enter>` → `=> 41`. `x.to_<Tab>` → popup with `to_s`/`to_i`/etc.
7. `Net::H<Tab>` → popup with `Net::HTTP`, `Net::HTTPHeader`, etc.
8. `@README<Tab>` → file picker; pick a file, token inserted
9. `!ls<Enter>` → command output rendered in history
10. `\<Enter>` mid-input → multi-line continuation
11. `Ctrl+R` → reverse search popup, type, accept
12. `Ctrl+O` → transcript mode; `/`-search; `[` to scrollback; `q` exit
13. `/focus` → focus mode active; toggle off restores
14. `/btw 2+2` → ephemeral overlay; Space dismisses
15. Mouse click on URL in history → opens browser; click+drag selects + copies
16. Resize terminal → all regions repaint cleanly
17. `Ctrl+L Ctrl+L` within 2s → screen clear (`/clear`-equivalent)
18. `/q` → alt-screen exit clean, terminal restored

`bundle exec rake test` reports `0 failures` throughout.

---

## 10. Out of scope (explicit non-goals)

- Network calls (no LLM, no Anthropic API integration — cclikesh is a framework, the shell using it brings its own AI if any)
- JetBrains/VS Code IDE integration
- Real Claude Code-specific commands (`/init`, `/agents`, `/mcp`, `/permissions`, etc.) — those are CC-product features, irrelevant to a generic shell framework
- Auto-update / self-installer

The shell **author** uses cclikesh to build their own slash commands; cclikesh provides the **rendering primitives**, not the commands themselves.
