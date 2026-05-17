# ptyblues integration sample

Runnable samples for recording, inspecting, and auto-E2E-testing a
baslash app via the external [ptyblues](https://github.com/bash0C7/ptyblues)
tool. baslash itself has no runtime or gemspec dependency on ptyblues —
the relationship is pure external-process.

For ergonomics, the root `Gemfile` wires the full ptyblues monorepo
sub-gem chain into the `:development, :test` groups via sibling paths
(`../ptyblues`, `../ptyblues/record`, `../ptyblues/viewer`,
`../ptyblues/inspect`, `../ptyblues/client-druby`,
`../ptyblues/client-cli`), so `bundle exec ttyblues …` works after a
single `bundle install`.

## Prereqs

- `bundle install` has succeeded in the baslash repo root
- The sibling ptyblues checkout exists at `../ptyblues` (standard
  `~/dev/src/<host>/<org>/<repo>` layout — `ghq get` it if missing)
- macOS (ptyblues is macOS-only at present)

## Files

| File | Purpose |
|---|---|
| `01_record_session.sh` | Record `echo_shell.rb` via the ttyblues hub (`serve` → `start` → `input` → `wait` → `stop`) |
| `02_inspect_session.sh` | Inspect the recorded session (`list` → `info` → `frames` → `semantic` → `export`) |
| `03_spec_e2e.rb` | Standalone automated E2E using `Ptyblues::Inspect::SpecDSL` — does **not** need the ttyblues hub |

## Run

From the baslash repo root:

```bash
# Manual record + inspect (uses the ttyblues DRb hub)
bash examples/ptyblues_recording/01_record_session.sh
bash examples/ptyblues_recording/02_inspect_session.sh

# Standalone automated E2E (no hub required)
bundle exec ruby examples/ptyblues_recording/03_spec_e2e.rb
```

## Cleanup

```bash
bundle exec ttyblues unserve              # stop the hub
rm -rf tmp/ptyblues/                      # drop recorded sqlite DBs
```

## Adapting for your own baslash app

`03_spec_e2e.rb` is the most copy-pasteable starting point. The
embedded `SPEC_SOURCE` HEREDOC follows the `session "label" do … end` +
`expect "label" do |captured| … end` DSL from
`ptyblues-inspect`. `captured` is a `Ptyblues::Inspect::Captured` —
useful methods include `contains?(substring)`, `match?(regex)`,
`output_text`, `output_text_clean`, `exit_status`, and `screen(rows:,
cols:)` for visible-grid assertions.
