# cclikesh

Claude Code-style interactive CLI shell framework, built on Reline + Ractor.

## Architecture

cclikesh runs in line mode on the terminal's main screen. Each turn prints
output, two `─` dividers, the Reline prompt, and a static footer
(status_rows + shortcuts_hint) as inline lines. Past turns flow into the
terminal's native scrollback. The animated working status_line above the
top divider is rewritten in place via ANSI cursor save/move/erase/restore.

Runtime dependencies: reline, unicode-display_width, logger.

- Single-process Ruby 4.0+, macOS only
- Main Ractor owns Reline (line-mode rendering)
- Slash handlers run in per-invocation Handler Ractors (true parallelism with UI)
- Mutable user state opt-in via `shareable_ref { ... }` State Ractor wrapper

### Concurrency principles

Application code follows six rules, enforced by an audit test (`test/test_thread_zero.rb`):

1. No `Thread.new` in application code (Ractor only)
2. Concurrency is `Ractor::Port` + `shareable_proc` based
3. Ractor-unsafe C extensions are isolated in a subprocess and reached via DRb
4. Unshareable resources (sockets, DB handles) are opened inside the owning Ractor
5. Messages crossing Ractor boundaries are frozen / shareable
6. Ruby 4.0+ Ractor API only (`#take` / `#yield` are not used)

## Quick start

```ruby
require "cclikesh"

Cclikesh.run do |shell|
  shell.header { |h| h.title "demo"; h.note "hi" }
  shell.on_submit do |args, ctx|
    ctx.display.append("you said: #{args.first}", style: :result)
  end
  shell.slash(:q) { |_, ctx| ctx.quit }
end
```

Run: `bundle exec ruby examples/echo_shell.rb`

## Using cclikesh from your own gem / project

cclikesh is not (yet) on RubyGems. Pull it directly from GitHub.

### 1. Add to your `Gemfile`

```ruby
source "https://rubygems.org"

gem "cclikesh", github: "bash0C7/cclikeinterabtivecshell"
```

Then:

```bash
bundle install
```

This brings in `cclikesh` itself plus its hard dependencies (`reline`, `drb`, `rinda`, `unicode-display_width`). `informers` is only needed if you also opt into `cclikesh-debug` (see below).

### 2. Write a shell

The single entry point is `Cclikesh.run`, which yields a Builder DSL:

```ruby
# my_shell.rb
require "cclikesh"

Cclikesh.run do |shell|
  shell.header do |h|
    h.logo     "✻"
    h.title    "my-shell"
    h.version  "v0.1.0"
    h.subtitle "Ruby #{RUBY_VERSION} · #{Dir.pwd}"
    h.note     "press /q to quit"
  end

  shell.shortcuts_hint "/q to quit"

  shell.on_submit do |args, ctx|
    line = args.first
    ctx.display.append("you typed: #{line}", style: :result)
  end

  shell.slash(:q, description: "exit") { |_args, ctx| ctx.quit }
end
```

Run it:

```bash
bundle exec ruby my_shell.rb
```

### 3. DSL reference (what you call on `shell`)

| Method | Purpose |
|---|---|
| `shell.header { \|h\| ... }` | Top banner. `h.logo / h.title / h.version / h.subtitle / h.note` (all optional). |
| `shell.info(name, order: N) { \|ctx\| ... }` | One segment of the info bar. Block returns a `String`. |
| `shell.status_row(name) { \|row, ctx\| ... }` | One row in the status footer. Use `row.icon`, `row.text`, `row.link(text:, state:)`, `row.bar(percent:, width:)`. |
| `shell.spinner_label { \|ctx\| ... }` | Spinner label. Return `:auto` or a custom `String`. |
| `shell.prompt_suggestion { \|ctx\| ... }` | Dimmed inline hint shown above the prompt. |
| `shell.shortcuts_hint "text"` | One-line shortcuts hint shown in the footer. |
| `shell.define_style(:name, fg:, bold:)` | Register a named style (e.g. `fg: :yellow, bold: true`). |
| `shell.shareable_ref(:name) { Obj.new }` | Wrap a mutable object in its own Ractor; call it via `ctx.shareable(:name).call(:method, *args)`. |
| `shell.on_start { \|ctx\| ... }` | Runs once right after shell init. Use for warm-up output. |
| `shell.on_quit { \|ctx\| ... }` | Runs once right before teardown. Use for save/cleanup. |
| `shell.on_submit { \|args, ctx\| ... }` | Fires when the user presses Enter. `args == [line].freeze`. Runs in a Handler Ractor. |
| `shell.on_tab { \|buf, pos\| ... }` | Reline completion proc. Return `Array<String>` (or `nil`). |
| `shell.slash(:name, description: ...) { \|args, ctx\| ... }` | Register `/name`. `args` is the parsed rest of the line. |
| `shell.btw { \|question, ctx\| ... }` | Register `/btw <text>`. Whatever the block returns is appended to the display. |

### 4. Inside your handler — what `ctx` lets you do

`ctx` is a thin proxy that talks to the main Ractor; it's safe to use from inside `on_submit` / slash blocks.

```ruby
# --- Output ---
ctx.display.append("line of text", style: :result, prompt: "irb> ")
ctx.display.dialog("boxed text", style: :result)

# Streaming "live" slot — show progress, then commit or discard
slot = ctx.display.open_live(style: :thinking)
3.times { |i| slot.update("step #{i + 1}/3 ..."); sleep 0.1 }
slot.commit                # finalize
# slot.discard             # erase if cancelled

# --- State (key/value, written values are auto-frozen) ---
ctx.state[:phase] = :working
phase = ctx.state[:phase]

# --- Shareable refs (mutable objects living in their own Ractor) ---
result = ctx.shareable(:evaluator).call(:evaluate, line)

# --- Logging (goes to the shell's stderr logger) ---
ctx.logger.info("submit: #{line.inspect}")

# --- Quit ---
ctx.quit
```

Built-in styles include `:result`, `:thinking`, `:dim`, `:error`. Add your own via `shell.define_style(...)`.

### 5. Concurrency rules for your own handlers

- `on_submit` runs in a **per-invocation Handler Ractor** — long work doesn't block the UI.
- Mutable state goes in `shareable_ref` (one Ractor per ref) or `ctx.state` (key/value on the main Ractor).
- Don't `Thread.new` inside handlers. If you need concurrency, spawn another Ractor or push work to a `shareable_ref`.
- Messages you pass across Ractor boundaries must be frozen / shareable; `ctx.state[...]=` freezes for you.

### 6. Optional: cclikesh-debug for session recording

`cclikesh-debug` is a separate sub-gem in the same repo. Add it to `:development` only:

```ruby
group :development do
  gem "cclikesh-debug",
      github: "bash0C7/cclikeinterabtivecshell",
      glob:   "cclikesh-debug/*.gemspec"
end
```

Then record a session of *your* shell:

```bash
bundle exec cclikesh-debug start my_shell.rb
bundle exec cclikesh-debug input  <session> "hello\r"
bundle exec cclikesh-debug capture <session>
bundle exec cclikesh-debug stop   <session>
bundle exec cclikesh-debug frames <session>
```

The resulting SQLite DB is chiebukuro-mcp compatible — you can grep / vec-search frames with the standard tooling.

## Examples

- `examples/echo_shell.rb` — minimal demo
- `examples/irb_shell/irb_shell.rb` — irb on cclikesh, uses `shell.shareable_ref(:evaluator) { IrbEvaluator.new }`
- `examples/zsh_shell/zsh_shell.rb` — zsh wrapper. Uses `shareable_ref(:cwd)` and `shareable_ref(:env)` to intercept `cd`/`export`/`unset`; everything else streams through `zsh -c` with `IO.select` line read.

## cclikesh-debug

Separate sub-gem (`cclikesh-debug/cclikesh-debug.gemspec`) for per-session debug recording:

- Per-session SQLite DB via `extralite` (Ractor-safe; chiebukuro-mcp compatible schema)
- sqlite-vec semantic search via `informers` + ruri-v3-310m-onnx
- asciinema cast export, agg/ffmpeg pipeline for gif/mp4/webm

### Recorder pipeline (v0.2.1)

Three Ractors stream the live session, and a subprocess hosts the embedder so the Ractor-unsafe ONNX layer never enters the main process:

```
PtyReader ──[:bytes]──▶ FrameBuilder ──[:frame]──▶ StorageWriter (extralite)
                            ▲
                            │ [:capture_with_snapshot]
                            │
                       Orchestrator (main Ractor)
                         ・DRb pulls debug_snapshot from the shell child
                         ・on stop, triggers embed_pending

on stop:
  exe/cclikesh-debug-embedder (subprocess, DRb)
        ──── proxy.embed(content) ────▶ EmbedStorageWriter (extralite, frame_vec)
```

`Thread.new` count in application code is 0.

```bash
bundle exec cclikesh-debug start examples/echo_shell.rb
bundle exec cclikesh-debug input <session> "hello\r"
bundle exec cclikesh-debug capture <session>
bundle exec cclikesh-debug stop <session>
bundle exec cclikesh-debug frames <session>
```

## Known v1 limitations

- macOS only (PTY usage in cclikesh-debug is macOS-specific)
- cclikesh-debug E2E test requires a real TTY; manual smoke on iTerm2 still pending

## Development

```bash
bundle install
bundle exec rake test
```

Sub-gem tests:

```bash
for f in cclikesh-debug/test/cclikesh-debug/test_*.rb; do
  bundle exec ruby -Icclikesh-debug/lib -Icclikesh-debug/test/cclikesh-debug "$f"
done
```

## License

MIT
