# baslash

baslash is a slash-command-driven framework for embedding interactive shell
DSLs in Ruby programs. It gives your app a Reline-edited prompt with
`/command` dispatch, a terminal title bar for live status, and natural
scrollback for output — no curses, no alt-screen. You bring the domain
logic, baslash wires the loop.

## Scope

- macOS only (Terminal.app and cmux verified)
- CRuby 4.x
- No curses, no alt-screen — output flows into the terminal's normal scrollback
- Status (cwd, var counts, phase, spinner) surfaced via OSC 0 title bar

## Architecture

- The main thread runs Reline and dispatches slash / on_submit handlers.
- Handlers execute **synchronously** on the main thread between prompts, so
  there is no race with user input.
- A small Ractor-based ticker repaints the title bar (spinner, info bar,
  status rows) while a handler runs.
- Mutable state that handlers want to share lives in `Baslash::Context.state`,
  bootstrapped via `shell.state(:name) { ... }` initializers and accessed
  in handlers as `ctx.state[:name]`.
- Slash bodies are plain Procs; they capture closures from the surrounding
  scope normally.

## Quick start

```ruby
require "baslash"

Baslash.run do |shell|
  shell.on_submit do |args, ctx|
    ctx.display.append("you said: #{args.first}", style: :result)
  end

  shell.slash(:q, description: "exit") { |_, ctx| ctx.quit }
end
```

Run it:

```bash
bundle exec ruby my_shell.rb
```

## Installation

baslash is not on RubyGems yet. Pull it directly from GitHub.

```ruby
# Gemfile
source "https://rubygems.org"

gem "baslash", github: "bash0C7/baslash"
```

```bash
bundle install
```

This brings in `baslash` and its runtime dependencies (`reline`,
`unicode-display_width`, `logger`).

## DSL reference

Everything is called on the `shell` object yielded by `Baslash.run`.

| Method | Purpose | Block args | Returns |
|---|---|---|---|
| `state(name, &block)` | Register a service-state initializer. The block runs once at boot; the returned object is stored under `ctx.state[name]`. | none | `self` (the builder, for chaining) |
| `on_start(&block)` | Runs once right after startup. | `(ctx)` (currently `nil`) | ignored |
| `on_quit(&block)` | Runs once right before teardown. | `(ctx)` (currently `nil`) | ignored |
| `on_submit(&block)` | Fires on Enter when the line is **not** a slash command. | `(args, ctx)` where `args == [line].freeze` | ignored |
| `on_tab(&block)` | Override the default Reline completion proc. | `(buffer, pos)` | `Array<String>` or `nil` |
| `slash(name, description:, &block)` | Register `/name`. | `(args, ctx)` where `args` is the parsed rest of the line | ignored |
| `btw(&block)` | Register `/btw <question>` shortcut. | `(question, ctx)` | string appended to display |
| `info(name, order: N, &block)` | One segment of the info bar (rendered in the title bar). | `(ctx)` | `String` |
| `status_row(name, &block)` | One row in the title-bar status. Use `row.icon`, `row.text`, `row.link(text:, state:)`, `row.bar(percent:, width:)`. | `(row, ctx)` | ignored |
| `spinner_label(&block)` | Spinner label override. | `(ctx)` | `:auto` or `String` |
| `prompt_suggestion(&block)` | Ghost text shown above the prompt. | `(ctx)` | `String` |
| `prompt_prefix(&block)` | Dynamic text rendered to the left of `> `, re-evaluated every prompt render. | `(main_ctx)` | `String` (or `nil` to omit) |
| `shortcuts_hint("text")` | One-line hint printed near the prompt at startup. | — | — |
| `header { \|h\| ... }` | Banner block: `h.logo`, `h.title`, `h.version`, `h.subtitle`, `h.note`. | yields a builder | — |
| `enable_debug_commands` | Register the built-in `/debug-*` slashes. | — | — |
| `define_style(name, **opts)` | **Deprecated.** No-op stub for back-compat with curses-era apps. Use the built-in semantic style names instead. | — | — |

## Handler context (`ctx`)

Inside a slash body or `on_submit`, `ctx` is a `SyncCtx` exposing:

| Call | Effect |
|---|---|
| `ctx.display.append(text, style: nil)` | Write one line to the terminal. |
| `ctx.display.open_live(style: nil)` | Open a live slot. Returns a slot with `update(text)`, `commit(final = nil)`, `discard`. Can also be called with a block — on normal exit the slot auto-commits, on raise it discards and re-raises. |
| `ctx.display.dialog(content, style: nil)` | Write a boxed dialog block. |
| `ctx.display.raw_emit(bytes)` | Write raw bytes (escape sequences included) directly to stdout. Intended for testing terminal handling. |
| `ctx.state[:key] = value` | Set a value in the per-shell key/value state (auto-frozen). |
| `ctx.state[:key]` | Read it back. |
| `ctx.state[name]` | Service objects registered via `shell.state` live here too — call methods on them directly (`ctx.state[:cwd].pwd`). |
| `ctx.logger` | The shell's stderr logger. |
| `ctx.quit` | Schedule shutdown after the current handler returns. |

Long-running handlers block the prompt, which is intentional — user input
cannot race with handler output. Pressing `Ctrl-C` while a handler runs
raises `Interrupt`, which baslash catches and logs as `^C`.

## Styling

Styles are SGR-based. There is no registration step; pass a symbol to
`ctx.display.append(..., style: :name)`.

**Semantic styles** (the ones the framework itself uses for status / meta
output, and what app code should reach for first):

| Style | Color |
|---|---|
| `:ok` | green |
| `:ng` | red |
| `:error` | red |
| `:warn` | yellow |
| `:thinking` | dim cyan |
| `:meta` | dim cyan |

`:result` is **intentionally pass-through** (unstyled). It exists so that
impl-execution output — the actual stdout of whatever the shell is
wrapping — stays in the user's default terminal color. Any unknown style
name is also pass-through.

**Primitive styles** are also accepted as a style name:

- Text styles: `:bold`, `:dim`, `:italic`, `:underline`, `:reverse`
- Foreground colors: `:black`, `:red`, `:green`, `:yellow`, `:blue`,
  `:magenta`, `:cyan`, `:white`

## Prompt

The default prompt is a bold cyan `> ` rendered only on the first row of
a multi-line edit buffer; continuation rows get an empty prefix so the
arrow doesn't repeat. `prompt_prefix` lets you inject dynamic text (e.g.
the current working directory) to the left of the arrow; it is
re-evaluated every iteration of the main loop.

## Examples

Three reference embeddings live under `examples/`:

- `examples/echo_shell.rb` — minimal demo. Echoes input back, exercises
  `info`, `status_row`, `spinner_label`, `btw`, live slots.
- `examples/zsh_shell/zsh_shell.rb` — zsh wrapper. Intercepts
  `cd`/`export`/`unset` via two state holders (`cwd`, `env`), streams
  everything else through `zsh -c` with line-buffered stdout/stderr.
  Uses `prompt_prefix` to keep the cwd visible at the prompt.
- `examples/irb_shell/irb_shell.rb` — irb evaluator on top of baslash.
  Demonstrates persistent `Binding`-holding state via `shell.state`.

Run them with:

```bash
bundle exec ruby examples/echo_shell.rb
bundle exec ruby examples/zsh_shell/zsh_shell.rb
```

## Concurrency model

- Handlers run synchronously on the main thread. There is no Ractor
  isolation around the handler body — your slash body is a normal Proc
  that can capture closures from the surrounding scope.
- Mutable shared state goes in `shell.state(:name) { ... }` (a regular
  Ruby object stored in `Baslash::Context.state`). Handlers read and
  mutate it as `ctx.state[:name].some_method`. Safe because handlers
  run sequentially on the main thread; the `Thread.new` ban (enforced
  by `test/test_thread_zero.rb`) keeps it that way.
- `ctx.state[...]` is a per-shell key/value bag (the value is frozen on
  write).
- The title-bar ticker is a single Ractor running on its own. Handlers
  do not interact with it directly; they just publish through
  `ctx.state[:phase]` and the ticker reads what it needs.
- Long-running handlers block the shell — by design. `Ctrl-C` aborts.
- Application code MUST NOT call `Thread.new`. `test/test_thread_zero.rb`
  enforces this for `lib/` and `examples/`.

## Testing

```bash
bundle exec rake test
```

`test/test_thread_zero.rb` audits `lib/` and `examples/` for any
`Thread.new` usage and fails the suite if it finds one.

## Appendix: Recording & Analysis with ptyblues

baslash apps can be recorded, inspected, and auto-tested end-to-end via
the external [ptyblues](https://github.com/bash0C7/ptyblues) tool.
baslash itself has **no runtime / gemspec dependency** on ptyblues; the
relationship is purely external-process. Any change, removal, or
non-installation of ptyblues has zero effect on baslash's own behaviour
or `rake test`.

For developer ergonomics, the root `Gemfile` wires the ptyblues
monorepo's sub-gems into the `:development, :test` groups via sibling
paths (`../ptyblues`, `../ptyblues/record`, `../ptyblues/viewer`,
`../ptyblues/inspect`, `../ptyblues/client-druby`,
`../ptyblues/client-cli`). After `bundle install`, `bundle exec ptyblues …`
works without any further `gem install` step.

### Quick start

```bash
# Record a session of any baslash app (echo_shell shown).
bash examples/ptyblues_recording/01_record_session.sh

# Inspect what was recorded: list / info / frames / semantic / export.
bash examples/ptyblues_recording/02_inspect_session.sh

# Standalone E2E (no hub required): SpecDSL spawns the PTY itself.
bundle exec ruby examples/ptyblues_recording/03_spec_e2e.rb
```

See `examples/ptyblues_recording/README.md` for what each script does
and how to extend the pattern for your own baslash app.

### External ptyblues repo

External tool: <https://github.com/bash0C7/ptyblues>

## License

MIT
