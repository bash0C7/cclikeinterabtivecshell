# cclikesh

Claude Code-style 3-region interactive CLI shell framework, built on curses + Ractor.

## Architecture

- Single-process Ruby 4.0+, macOS only
- Main Ractor owns Reline + curses (3-region UI: header bar, scrollable body, input row)
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

## Examples

- `examples/echo_shell.rb` — minimal demo
- `examples/irb_shell/irb_shell.rb` — irb on cclikesh, uses `shell.shareable_ref(:evaluator) { IrbEvaluator.new }`

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

- macOS only (curses + PTY usage is macOS-specific)
- cclikesh-debug E2E test requires a real TTY; manual smoke (WINCH / popup) on iTerm2 still pending

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
