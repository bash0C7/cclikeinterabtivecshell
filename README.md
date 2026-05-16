# baslash

Slash-command-driven Ruby framework for embedded interactive shell DSLs.

baslash provides a reusable backbone — Reline-based prompt editing, slash
command dispatch, per-invocation HandlerRactor isolation, terminal title
bar status — for Ruby programs that want a `zsh`-style interactive shell
surface tailored to their domain. Examples (`examples/echo_shell.rb`,
`examples/zsh_shell/`, `examples/irb_shell/`) show three concrete embeddings.

## Scope

- macOS only (Terminal.app and cmux verified)
- CRuby 4.x (uses Ractor)
- Body content flows naturally to terminal scrollback (no curses, no alt-screen)
- Status (cwd, var count, phase, spinner) appears in the terminal title bar via OSC 0

## Architecture

- Single-process Ruby 4.0+, macOS only
- Main Ractor owns Reline + the terminal title bar (OSC 0 status)
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
require "baslash"

Baslash.run do |shell|
  shell.on_submit do |args, ctx|
    ctx.display.append("you said: #{args.first}", style: :result)
  end
  shell.slash(:q) { |_, ctx| ctx.quit }
end
```

Run: `bundle exec ruby examples/echo_shell.rb`

## Terminal scrollback

baslash drives Reline directly on the terminal's main screen. It does not
enter the terminal's alt-screen buffer, and it does not draw curses chrome.
Submitted lines and handler output flow naturally into the terminal's
scrollback buffer; your terminal's native scroll wheel and shortcuts keep
working.

Status (cwd / var counts / current phase / spinner) is published via OSC 0
to the terminal's title bar, so the main screen stays clean.

## Using baslash from your own gem / project

baslash is not (yet) on RubyGems. Pull it directly from GitHub.

### 1. Add to your `Gemfile`

```ruby
source "https://rubygems.org"

gem "baslash", github: "bash0C7/cclikeinterabtivecshell"
```

Then:

```bash
bundle install
```

This brings in `baslash` itself plus its hard dependencies (`reline`, `drb`,
`rinda`, `unicode-display_width`). `informers` is only needed if you also
opt into `baslash-debug` (see below).

### 2. Write a shell

The single entry point is `Baslash.run`, which yields a Builder DSL:

```ruby
# my_shell.rb
require "baslash"

Baslash.run do |shell|
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
| `shell.info(name, order: N) { \|ctx\| ... }` | One segment of the info bar (rendered in the title). Block returns a `String`. |
| `shell.status_row(name) { \|row, ctx\| ... }` | One row in the status footer. Use `row.icon`, `row.text`, `row.link(text:, state:)`, `row.bar(percent:, width:)`. |
| `shell.spinner_label { \|ctx\| ... }` | Spinner label. Return `:auto` or a custom `String`. |
| `shell.prompt_suggestion { \|ctx\| ... }` | Dimmed inline hint shown above the prompt. |
| `shell.shortcuts_hint "text"` | One-line shortcuts hint shown alongside the prompt. |
| `shell.define_style(:name, fg:, bold:)` | Register an ANSI style for `ctx.display.append(..., style: :name)`. |
| `shell.shareable_ref(:name) { Obj.new }` | Wrap a mutable object in its own Ractor; call it via `ctx.shareable(:name).call(:method, *args)`. |
| `shell.on_start { \|ctx\| ... }` | Runs once right after startup. Use for warm-up output. |
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

### 6. Optional: baslash-debug for session recording

`baslash-debug` is a separate sub-gem in the same repo. Add it to `:development` only:

```ruby
group :development do
  gem "baslash-debug",
      github: "bash0C7/cclikeinterabtivecshell",
      glob:   "baslash-debug/*.gemspec"
end
```

Then record a session of *your* shell:

```bash
bundle exec baslash-debug start my_shell.rb
bundle exec baslash-debug input  <session> "hello\r"
bundle exec baslash-debug capture <session>
bundle exec baslash-debug stop   <session>
bundle exec baslash-debug frames <session>
```

The resulting SQLite DB is chiebukuro-mcp compatible — you can grep / vec-search frames with the standard tooling.

## Examples

- `examples/echo_shell.rb` — minimal demo
- `examples/irb_shell/irb_shell.rb` — irb on baslash, uses `shell.shareable_ref(:evaluator) { IrbEvaluator.new }`
- `examples/zsh_shell/zsh_shell.rb` — zsh wrapper. Uses `shareable_ref(:cwd)` and `shareable_ref(:env)` to intercept `cd`/`export`/`unset`; everything else streams through `zsh -c` with `IO.select` line read.

## baslash-debug

Separate sub-gem (`baslash-debug/baslash-debug.gemspec`) for per-session debug recording:

- Per-session SQLite DB via `extralite` (Ractor-safe; chiebukuro-mcp compatible schema)
- sqlite-vec semantic search via `informers` + ruri-v3-310m-onnx
- asciinema cast export, agg/ffmpeg pipeline for gif/mp4/webm

### Recorder pipeline

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
  exe/baslash-debug-embedder (subprocess, DRb)
        ──── proxy.embed(content) ────▶ EmbedStorageWriter (extralite, frame_vec)
```

`Thread.new` count in application code is 0.

```bash
bundle exec baslash-debug start examples/echo_shell.rb
bundle exec baslash-debug input <session> "hello\r"
bundle exec baslash-debug capture <session>
bundle exec baslash-debug stop <session>
bundle exec baslash-debug frames <session>
```

## Known limitations

- macOS only (Terminal.app and cmux verified)
- baslash-debug E2E test requires a real TTY

## Development

```bash
bundle install
bundle exec rake test
```

Sub-gem tests:

```bash
for f in baslash-debug/test/baslash-debug/test_*.rb; do
  bundle exec ruby -Ibaslash-debug/lib -Ibaslash-debug/test/baslash-debug "$f"
done
```

## License

MIT
