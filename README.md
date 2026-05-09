# cclikesh

Claude Code-style 3-region interactive CLI shell framework for Ruby 4.0+.

This is the **Plan 1 (Foundation MVP)** — single-process Ractor architecture
with line-buffered I/O. dRuby split, reline, full display engine, info bar,
and slash command parsing arrive in subsequent plans.

See [`docs/superpowers/specs/2026-05-09-cclikesh-design.md`](docs/superpowers/specs/2026-05-09-cclikesh-design.md)
for the full design and [`docs/superpowers/plans/`](docs/superpowers/plans/)
for the implementation plans.

## Status

Plan 1 (foundation) implemented:
- `Cclikesh.run` entry point with Builder DSL
- `on_submit` and `slash` registration
- `ctx.display.append` and `ctx.state[]` and `ctx.quit`
- ts4r-backed tuple space, three-Ractor split (Render / Input / Main)
- Line-buffered file-based I/O (stdin/stdout integration in Plan 2)

## Try the example

```sh
bundle install
mkdir -p tmp
printf "hello\n/quit\n" > tmp/input.txt
: > tmp/output.txt
bundle exec ruby -Ilib examples/echo_shell.rb tmp/input.txt tmp/output.txt
cat tmp/output.txt
```

## Test

```sh
bundle exec rake test
```

## Roadmap

- Plan 2: dRuby split (fork+exec, separate processes), reline, real terminal control
- Plan 3: Display engine (live slot, dialog, styles)
- Plan 4: Info layer (spinner, segments, idle_phrases)
- Plan 5: Command system (full slash, state hooks, before/after)
- Plan 6: Logger & Ruby::Box isolation
- Plan 7: Example irb shell
