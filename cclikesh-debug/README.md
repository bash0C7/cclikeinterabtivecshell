## PTY Recording (Spec B)

`cclikesh-debug` can record any TUI binary running under a PTY, drive it
from a Ruby DSL spec, and replay or hex-dump the result. The recording
lives in the same SQLite store as cclikesh framework sessions, in two
dedicated tables (`pty_sessions`, `pty_events`).

### Subcommands

| Command                                | Purpose                                            |
| -------------------------------------- | -------------------------------------------------- |
| `cclikesh-debug play <spec.rb>`        | Run a DSL spec, persist + run `expect` blocks.     |
| `cclikesh-debug replay <session_uuid>` | Stream recorded output to stdout with real timing. |
| `cclikesh-debug dump <session_uuid>`   | Emit hex/ascii per event for grep-style inspection.|
| `cclikesh-debug pty-list`              | List recorded sessions newest-first.               |

All four accept `--db PATH` (default `tmp/longrun/cclikesh-debug.sqlite`
under the current working directory, falling back to `./cclikesh-debug.sqlite`).
`replay` accepts `--speed N` (default 1.0; 0 disables pacing). `dump`
accepts `--io i|o|both` (default both).

### Spec DSL

    session "describe the run" do
      timeout 15
      spawn argv: %w[bundle exec ruby examples/echo_shell.rb],
            cols: 80, rows: 24,
            env:  { "TERM" => "xterm-256color" }
      wait 0.5
      send "hello\n"
      wait 0.5
      send "/q\r"
    end

    expect "echoes hello back" do |c|
      c.contains?("hello")
    end

    expect "exits cleanly" do |c|
      c.exit_status == 0
    end

Exit codes for `play`:

- `0` — every `expect` passed and the child exited within the timeout
- `1` — at least one `expect` returned falsy or raised
- `2` — the child was killed for exceeding the spec timeout
- `3` — the spec raised before recording started (DSL error)

`expect` blocks receive a frozen `Captured` snapshot exposing
`output_bytes`, `output_text`, `output_text_clean`, `input_log`,
`frames`, `exit_status`, `session_uuid`, `contains?(s)`, and `match?(regex)`.
