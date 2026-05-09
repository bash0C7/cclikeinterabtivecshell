# cclikesh

Claude Code-style 3-region interactive CLI shell framework for Ruby 4.0+.

This is the **Plan 2 (dRuby split + reline)** — Cclikesh forks an impl process
and an F (framework) process; impl hosts a HandlerRegistry over UNIX-socket
dRuby, F runs reline for stdin and a Thread-based renderer for stdout.
Full display engine, info bar, and richer slash command parsing arrive in
subsequent plans.

See [`docs/superpowers/specs/2026-05-09-cclikesh-design.md`](docs/superpowers/specs/2026-05-09-cclikesh-design.md)
for the full design and [`docs/superpowers/plans/`](docs/superpowers/plans/)
for the implementation plans.

## Status

Plan 2 (dRuby split + reline) complete. Cclikesh forks an impl process and an
F (framework) process; impl hosts a HandlerRegistry over UNIX-socket dRuby; F
runs reline for stdin and a Thread-based renderer for stdout. PTY-driven E2E
coverage lands in the next change.

## Try the example

```sh
bundle install
bundle exec ruby -Ilib examples/echo_shell.rb
```

## Test

```sh
bundle exec rake test
```

## Roadmap

- Plan 2: dRuby split (fork, separate processes), reline, real terminal control - done
- Plan 3: 3-region rendering with Display engine (info layer + spinner + live slot)
- Plan 4: Info layer (spinner, segments, idle_phrases)
- Plan 5: Command system (full slash, state hooks, before/after)
- Plan 6: Logger & Ruby::Box isolation
- Plan 7: Example irb shell
