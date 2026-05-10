# cclikesh

Claude Code-style 3-region interactive CLI shell framework, built on curses + Ractor.

## Architecture

- Single-process Ruby 4.0+, macOS only
- Main Ractor owns Reline + curses (3-region UI: header bar, scrollable body, input row)
- Slash handlers run in per-invocation Handler Ractors (true parallelism with UI)
- Mutable user state opt-in via `shareable_ref { ... }` State Ractor wrapper

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

- Per-session SQLite DB (chiebukuro-mcp compatible schema)
- sqlite-vec semantic search via informers + ruri-v3-310m-onnx
- asciinema cast export, agg/ffmpeg pipeline for gif/mp4/webm

```bash
bundle exec cclikesh-debug start examples/echo_shell.rb
bundle exec cclikesh-debug input <session> "hello\r"
bundle exec cclikesh-debug capture <session>
bundle exec cclikesh-debug stop <session>
bundle exec cclikesh-debug frames <session>
```

## Known v1 limitations

- macOS only (curses + PTY usage is macOS-specific)
- cclikesh-debug recorder pipeline has Ractor-safety issues with sqlite3 (StorageWriter needs to be a Thread, not a Ractor — planned for v0.2.1)
- cclikesh-debug E2E test is omitted in headless test runs (requires a real TTY; manual verification needed)
- `on_tab` handler in the DSL is captured but not yet wired into Reline's tab completion path

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
