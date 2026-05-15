# Curses + Non-Alt-Screen Diagnostic Strategy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-contained diagnostic + verification harness that can reproduce R1/R2/R3 residual curses bugs in cmux-like env conditions inside `bundle exec rake test`, with structured layout state captured to a per-session log.

**Architecture:** Add a tiny `Cclikesh::LayoutDiag` module that appends one line per layout-affecting call site when `ENV["CCLIKESH_LAYOUT_DIAG"]` is set to a path. Extend `PtyRunner` with `clear_size_env:` mode (deletes LINES/COLUMNS instead of overwriting) and a `script_resize(cols, rows)` API (sets `@r.winsize` to fire SIGWINCH). Extend `SpecDSL` to forward both, auto-inject a per-session diag log path, parse it post-run, and expose `captured.diag_entries`. Add three regression specs that opt into the new mode and assert on byte stream + diag entries.

**Tech Stack:** Ruby, test-unit, ncurses (Ruby `curses` gem, byte-oriented on macOS), Reline, the existing in-tree PTY harness (`cclikesh-debug`).

**Reference spec:** `docs/superpowers/specs/2026-05-15-curses-noalt-diag-strategy-design.md`
**Reference handoff (for theory list e–j):** `docs/superpowers/handoff/2026-05-15-curses-noalt-residual-bugs.md`

---

## File Structure

**New files:**
- `lib/cclikesh/layout_diag.rb` — `Cclikesh::LayoutDiag.log(tag)` module. Single responsibility: append one structured line per call when `ENV["CCLIKESH_LAYOUT_DIAG"]` names a writable path.
- `test/test_layout_diag.rb` — unit test for the module above.
- `cclikesh-debug/test/specs/cmux_env_resize_cursor.rb` — R1 reproduction spec.
- `cclikesh-debug/test/specs/cmux_env_slash_layout.rb` — R2 reproduction spec.
- `cclikesh-debug/test/specs/cmux_env_resize_divider.rb` — R3 reproduction spec.

**Modified files:**
- `lib/cclikesh/runner.rb` — wire `LayoutDiag.log` at two sites; require the new module.
- `lib/cclikesh/chrome.rb` — wire `LayoutDiag.log` at four sites; require the new module.
- `lib/cclikesh/display.rb` — wire `LayoutDiag.log` at one site; require the new module.
- `cclikesh-debug/lib/cclikesh/debug/pty_runner.rb` — add `clear_size_env:` kwarg + `ScriptApi#resize` + `PtyRunner#script_resize`.
- `cclikesh-debug/test/cclikesh-debug/test_pty_runner.rb` — unit tests for the two new behaviours.
- `cclikesh-debug/lib/cclikesh/debug/spec_dsl.rb` — `SessionScope#spawn` accepts `clear_size_env:`; add `SessionScope#resize`; `SpecDSL.run` forwards kwargs, auto-injects diag log path, parses post-run, passes to Captured.
- `cclikesh-debug/test/cclikesh-debug/test_spec_dsl.rb` — unit tests for the new DSL surface.
- `cclikesh-debug/lib/cclikesh/debug/captured.rb` — `from_storage` and `initialize` accept `diag_entries:`; `attr_reader :diag_entries`.

---

## Build Order (TDD per task)

Tasks 1–4: build and wire `LayoutDiag`.
Tasks 5–6: extend `PtyRunner` with the two new behaviours, each TDD'd in isolation.
Task 7: extend `SpecDSL` + `Captured` to surface diag entries to specs.
Tasks 8–10: write the three R1/R2/R3 reproduction specs.
Task 11: full-suite verification + handoff note.

The acceptance criterion in the spec (§7) is that the new specs are non-trivially exercising the new infrastructure. They may fail (revealing the real bug — that's a follow-up) or green (which itself is a finding).

---

### Task 1: `Cclikesh::LayoutDiag` module + unit test

**Files:**
- Create: `lib/cclikesh/layout_diag.rb`
- Test: `test/test_layout_diag.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/test_layout_diag.rb
require_relative "test_helper"
require "tmpdir"
require "cclikesh/layout_diag"

class TestLayoutDiag < Test::Unit::TestCase
  def setup
    @log_path = File.join(Dir.tmpdir, "layout-diag-test-#{Process.pid}-#{rand(1<<32).to_s(16)}.log")
    @prev_env = ENV["CCLIKESH_LAYOUT_DIAG"]
  end

  def teardown
    ENV["CCLIKESH_LAYOUT_DIAG"] = @prev_env
    File.unlink(@log_path) if File.exist?(@log_path)
  end

  def test_no_op_when_env_unset
    ENV["CCLIKESH_LAYOUT_DIAG"] = nil
    Cclikesh::LayoutDiag.log("noop")
    assert_not File.exist?(@log_path), "no file should be created when env unset"
  end

  def test_no_op_when_env_blank
    ENV["CCLIKESH_LAYOUT_DIAG"] = ""
    Cclikesh::LayoutDiag.log("noop")
    assert_not File.exist?(@log_path), "no file when env blank"
  end

  def test_appends_one_line_per_call
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
    Cclikesh::LayoutDiag.log("first")
    Cclikesh::LayoutDiag.log("second")
    lines = File.readlines(@log_path)
    assert_equal 2, lines.size
    assert_match(/\bfirst\b/, lines[0])
    assert_match(/\bsecond\b/, lines[1])
  end

  def test_line_contains_expected_fields
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
    Cclikesh::LayoutDiag.log("Chrome.init")
    line = File.read(@log_path)
    assert_match(/^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/, line)  # iso8601(3)
    assert_match(/Chrome\.init/, line)
    assert_match(/curses\.lines=/, line)
    assert_match(/curses\.cols=/, line)
    assert_match(/maxyx=/, line)
    assert_match(/winsize=/, line)
    assert_match(/env_lines=/, line)
    assert_match(/env_cols=/, line)
  end

  def test_swallows_disk_failure
    ENV["CCLIKESH_LAYOUT_DIAG"] = "/nonexistent_dir_for_diag_test/diag.log"
    # Must not raise even when the path is unwritable.
    assert_nothing_raised do
      Cclikesh::LayoutDiag.log("disk-fail")
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell
bundle exec rake test TEST=test/test_layout_diag.rb
```
Expected: `LoadError: cannot load such file -- cclikesh/layout_diag` (the file doesn't exist yet).

- [ ] **Step 3: Implement the module**

Create `lib/cclikesh/layout_diag.rb`:

```ruby
# frozen_string_literal: true

require "time"

module Cclikesh
  module LayoutDiag
    def self.log(tag)
      path = ENV["CCLIKESH_LAYOUT_DIAG"]
      return if path.nil? || path.empty?

      lines  = (defined?(Curses) ? (Curses.lines rescue nil) : nil)
      cols   = (defined?(Curses) ? (Curses.cols  rescue nil) : nil)
      maxyx  = begin
        (defined?(Curses) && Curses.respond_to?(:stdscr) && Curses.stdscr) ? Curses.stdscr.maxyx : nil
      rescue StandardError
        nil
      end
      winsz  = begin
        require "io/console"
        c = IO.console
        c ? c.winsize : nil
      rescue StandardError
        nil
      end
      env_l  = ENV["LINES"]
      env_c  = ENV["COLUMNS"]
      File.open(path, "a") do |f|
        f.puts "[#{Time.now.iso8601(3)}] #{tag} curses.lines=#{lines.inspect} curses.cols=#{cols.inspect} maxyx=#{maxyx.inspect} winsize=#{winsz.inspect} env_lines=#{env_l.inspect} env_cols=#{env_c.inspect}"
      end
    rescue StandardError
      # Best-effort debug instrumentation: must NEVER raise from runtime code.
      # The contract for this module IS "best effort, debug-only", so the
      # blanket rescue is by design (cf. spec §4.5 / CLAUDE.md exception note).
      nil
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rake test TEST=test/test_layout_diag.rb`
Expected: 5 tests, 0 failures, 0 errors.

If any individual test fails, fix the implementation and re-run before continuing.

- [ ] **Step 5: Commit**

Use the git-via-subagent rule from `~/.claude/CLAUDE.md`. Dispatch a `general-purpose` agent with the prompt:

> Working dir: /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell. Stage `lib/cclikesh/layout_diag.rb` and `test/test_layout_diag.rb` only. Commit message:
>
> `feat(layout_diag): structured per-call-site curses layout log gated on CCLIKESH_LAYOUT_DIAG`
>
> Include Co-Authored-By footer per CLAUDE.md. Report SHA and short status. Do not stage cclikesh-debug/tmp/.

---

### Task 2: Wire `LayoutDiag.log` into `Runner`

**Files:**
- Modify: `lib/cclikesh/runner.rb` (add `require_relative "layout_diag"` near other requires; insert two `Cclikesh::LayoutDiag.log("...")` calls)
- Test: `test/test_runner_layout_diag.rb` (new)

- [ ] **Step 1: Write the failing test**

This test exercises `init_curses` directly inside the test process and asserts log lines appear at the documented sites. It uses the same direct-`Curses.init_screen` pattern as `test/test_chrome.rb`.

```ruby
# test/test_runner_layout_diag.rb
require_relative "test_helper"
require "tmpdir"
require "curses"
require "cclikesh/runner"

class TestRunnerLayoutDiag < Test::Unit::TestCase
  def setup
    @log_path = File.join(Dir.tmpdir, "runner-diag-#{Process.pid}-#{rand(1<<32).to_s(16)}.log")
    @prev_env = ENV["CCLIKESH_LAYOUT_DIAG"]
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
  end

  def teardown
    ENV["CCLIKESH_LAYOUT_DIAG"] = @prev_env
    File.unlink(@log_path) if File.exist?(@log_path)
    Curses.close_screen rescue nil
  end

  def test_init_curses_emits_diag_after_init_screen
    Cclikesh::Runner.init_curses
    assert File.exist?(@log_path), "diag log must exist after init_curses"
    body = File.read(@log_path)
    assert_match(/Runner\.init_curses\.after_init_screen/, body)
  end

  def test_sync_curses_to_terminal_size_emits_diag
    Curses.init_screen
    File.write(@log_path, "")  # truncate after init_screen so the test only sees this call
    Cclikesh::Runner.sync_curses_to_terminal_size
    body = File.read(@log_path)
    assert_match(/Runner\.sync_curses_to_terminal_size/, body)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rake test TEST=test/test_runner_layout_diag.rb`
Expected: both tests fail (no diag log lines emitted).

- [ ] **Step 3: Wire the calls**

Edit `lib/cclikesh/runner.rb`:

Add this require near the top, with the other `require_relative` lines (around line 6):

```ruby
require_relative "layout_diag"
```

Inside `def self.init_curses`, after the `sync_curses_to_terminal_size` call (currently around line 147), add:

```ruby
      Cclikesh::LayoutDiag.log("Runner.init_curses.after_init_screen")
```

Place it AFTER the `sync_curses_to_terminal_size` line so the values logged include the post-sync state. Final fragment:

```ruby
    def self.init_curses
      sync_terminal_env_pre_init
      Curses.init_screen
      sync_curses_to_terminal_size
      Cclikesh::LayoutDiag.log("Runner.init_curses.after_init_screen")
      Curses.cbreak
      # ...rest unchanged
```

Inside `def self.sync_curses_to_terminal_size` (currently around line 174), add `LayoutDiag.log` AFTER the `Curses.resizeterm` call. Final method:

```ruby
    def self.sync_curses_to_terminal_size
      require "io/console"
      console = IO.console
      return if console.nil?
      rows, cols = console.winsize
      return if rows.nil? || cols.nil? || rows <= 0 || cols <= 0
      Curses.resizeterm(rows, cols) if Curses.respond_to?(:resizeterm)
      Cclikesh::LayoutDiag.log("Runner.sync_curses_to_terminal_size")
    rescue Errno::ENOTTY, IOError => e
      Cclikesh::Context.logger.error("winsize query failed: #{e.class}: #{e.message}") rescue nil
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rake test TEST=test/test_runner_layout_diag.rb`
Expected: 2 tests, 0 failures, 0 errors.

Also re-run the prior task's test to ensure no regression: `bundle exec rake test TEST=test/test_layout_diag.rb`. Expected: 5 tests, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

Dispatch git-via-subagent. Stage `lib/cclikesh/runner.rb` and `test/test_runner_layout_diag.rb`. Commit message:

`feat(runner): emit LayoutDiag at init_curses and sync_curses_to_terminal_size`

---

### Task 3: Wire `LayoutDiag.log` into `Chrome`

**Files:**
- Modify: `lib/cclikesh/chrome.rb`
- Test: `test/test_chrome_layout_diag.rb` (new)

- [ ] **Step 1: Write the failing test**

```ruby
# test/test_chrome_layout_diag.rb
require_relative "test_helper"
require "tmpdir"
require "curses"
require "cclikesh/style"
require "cclikesh/chrome"

class TestChromeLayoutDiag < Test::Unit::TestCase
  def setup
    @log_path = File.join(Dir.tmpdir, "chrome-diag-#{Process.pid}-#{rand(1<<32).to_s(16)}.log")
    @prev_env = ENV["CCLIKESH_LAYOUT_DIAG"]
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
  end

  def teardown
    ENV["CCLIKESH_LAYOUT_DIAG"] = @prev_env
    Cclikesh::Chrome.close
    Curses.close_screen
    File.unlink(@log_path) if File.exist?(@log_path)
  rescue
    nil
  end

  def test_chrome_init_emits_tag
    File.write(@log_path, "")
    Cclikesh::Chrome.init
    body = File.read(@log_path)
    assert_match(/Chrome\.init/, body)
    assert_match(/Chrome\.draw_dividers/, body)  # init calls draw_dividers internally
  end

  def test_handle_resize_emits_before_and_after_tags
    Cclikesh::Chrome.init
    File.write(@log_path, "")
    Cclikesh::Chrome.handle_resize
    body = File.read(@log_path)
    assert_match(/Chrome\.handle_resize\.before/, body)
    assert_match(/Chrome\.handle_resize\.after_resizeterm/, body)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rake test TEST=test/test_chrome_layout_diag.rb`
Expected: both tests fail.

- [ ] **Step 3: Wire the calls**

Edit `lib/cclikesh/chrome.rb`:

Add at the top with other requires (around line 5):

```ruby
require_relative "layout_diag"
```

In `def self.init` (currently around line 45), add `LayoutDiag.log` as the FIRST line of the method body (before allocating `@footer_win`):

```ruby
    def self.init
      Cclikesh::LayoutDiag.log("Chrome.init")
      @footer_win = Curses::Window.new(FOOTER_HEIGHT, Curses.cols,
                                        Curses.lines - FOOTER_HEIGHT, 0)
      @spinner_started_at = nil
      @winsize_dirty = false
      setup_breath_colors
      draw_dividers
    end
```

In `def self.draw_dividers` (currently around line 194), add `LayoutDiag.log` as the FIRST line:

```ruby
    def self.draw_dividers
      Cclikesh::LayoutDiag.log("Chrome.draw_dividers")
      width = Curses.cols
      # ...rest unchanged
```

In `def self.handle_resize` (currently around line 174), add ONE log call as the first executable line and a SECOND after the `sync_curses_to_terminal_size` call. Final method:

```ruby
    def self.handle_resize
      Cclikesh::LayoutDiag.log("Chrome.handle_resize.before")
      return unless @footer_win
      Cclikesh::Runner.sync_curses_to_terminal_size if Cclikesh::Runner.respond_to?(:sync_curses_to_terminal_size)
      Cclikesh::LayoutDiag.log("Chrome.handle_resize.after_resizeterm")
      @footer_win.resize(FOOTER_HEIGHT, Curses.cols)
      @footer_win.move(Curses.lines - FOOTER_HEIGHT, 0)
      Curses.stdscr.clear
      draw_dividers
      Display.refresh if defined?(Display) && Display.respond_to?(:refresh)
      Curses.doupdate
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rake test TEST=test/test_chrome_layout_diag.rb`
Expected: 2 tests, 0 failures, 0 errors.

Re-run existing chrome tests to ensure no regression: `bundle exec rake test TEST=test/test_chrome.rb`. Expected: prior pass count, no new failures.

- [ ] **Step 5: Commit**

Stage `lib/cclikesh/chrome.rb` and `test/test_chrome_layout_diag.rb`. Commit:

`feat(chrome): emit LayoutDiag at init, draw_dividers, and handle_resize boundaries`

---

### Task 4: Wire `LayoutDiag.log` into `Display.refresh`

**Files:**
- Modify: `lib/cclikesh/display.rb`
- Test: `test/test_display_layout_diag.rb` (new)

- [ ] **Step 1: Write the failing test**

```ruby
# test/test_display_layout_diag.rb
require_relative "test_helper"
require "tmpdir"
require "curses"
require "cclikesh/style"
require "cclikesh/chrome"
require "cclikesh/display"

class TestDisplayLayoutDiag < Test::Unit::TestCase
  def setup
    @log_path = File.join(Dir.tmpdir, "display-diag-#{Process.pid}-#{rand(1<<32).to_s(16)}.log")
    @prev_env = ENV["CCLIKESH_LAYOUT_DIAG"]
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
    Cclikesh::Chrome.init
    Cclikesh::Display.init
  end

  def teardown
    ENV["CCLIKESH_LAYOUT_DIAG"] = @prev_env
    Cclikesh::Display.close
    Cclikesh::Chrome.close
    Curses.close_screen
    File.unlink(@log_path) if File.exist?(@log_path)
  rescue
    nil
  end

  def test_refresh_emits_diag
    File.write(@log_path, "")
    Cclikesh::Display.refresh
    body = File.read(@log_path)
    assert_match(/Display\.refresh/, body)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rake test TEST=test/test_display_layout_diag.rb`
Expected: 1 test fail.

- [ ] **Step 3: Wire the call**

Edit `lib/cclikesh/display.rb`:

Add at the top with other requires (around line 5):

```ruby
require_relative "layout_diag"
```

In `def self.refresh` (currently around line 93), add as the FIRST executable line (before the `return unless @pad` guard):

```ruby
    def self.refresh
      Cclikesh::LayoutDiag.log("Display.refresh")
      return unless @pad
      # ...rest unchanged
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rake test TEST=test/test_display_layout_diag.rb`
Expected: 1 test, 0 failures.

Re-run `test/test_display.rb` to ensure no regression.

- [ ] **Step 5: Commit**

Stage `lib/cclikesh/display.rb` and `test/test_display_layout_diag.rb`. Commit:

`feat(display): emit LayoutDiag at refresh entry`

---

### Task 5: PtyRunner — `clear_size_env:` mode

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/pty_runner.rb`
- Modify: `cclikesh-debug/test/cclikesh-debug/test_pty_runner.rb`

- [ ] **Step 1: Write the failing test**

Append to `cclikesh-debug/test/cclikesh-debug/test_pty_runner.rb` (inside `class TestPtyRunner`):

```ruby
  def test_clear_size_env_strips_lines_and_columns
    # /usr/bin/env prints the env vars set inside the child. With the new
    # mode, COLUMNS/LINES must NOT appear (the child should only know the
    # PTY's size via TIOCGWINSZ, mirroring the user's cmux env).
    sink = ->(ts:, dir:, bytes:) {}
    events_collected = []
    sink_capture = ->(ts:, dir:, bytes:) { events_collected << { ts: ts, dir: dir, bytes: bytes } }
    runner = Cclikesh::Debug::PtyRunner.new(
      argv:        ["/usr/bin/env"],
      cols:        120,
      rows:        40,
      env:         { "COLUMNS" => "999", "LINES" => "999" }, # deliberately bogus to prove they're cleared
      timeout_sec: 5.0,
      event_sink:  sink_capture,
      clear_size_env: true,
    )
    status = runner.run
    output = events_collected.select { |e| e[:dir] == "o" }.map { |e| e[:bytes] }.join.b
    assert_equal 0, status
    assert_no_match(/^COLUMNS=/m, output, "COLUMNS must not appear in env output")
    assert_no_match(/^LINES=/m,   output, "LINES must not appear in env output")
  end

  def test_clear_size_env_default_false_preserves_existing_behavior
    sink_capture = ->(ts:, dir:, bytes:) { (@ev ||= []) << { ts: ts, dir: dir, bytes: bytes } }
    @ev = []
    runner = Cclikesh::Debug::PtyRunner.new(
      argv:        ["/usr/bin/env"],
      cols:        120,
      rows:        40,
      env:         {},
      timeout_sec: 5.0,
      event_sink:  sink_capture,
    )
    status = runner.run
    output = @ev.select { |e| e[:dir] == "o" }.map { |e| e[:bytes] }.join.b
    assert_equal 0, status
    assert_match(/^COLUMNS=120/m, output)
    assert_match(/^LINES=40/m,    output)
  end
```

Note: test-unit's negative form is `assert_no_match` (NOT `refute_match`, which is minitest). The `m` (multiline) flag is required so `^` matches at line beginnings within the multi-line env dump.

- [ ] **Step 2: Run to verify failure**

Run:
```
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/cclikesh-debug
bundle exec rake test TEST=test/cclikesh-debug/test_pty_runner.rb
```
Expected: `test_clear_size_env_strips_lines_and_columns` fails with `ArgumentError: unknown keyword: :clear_size_env`.

- [ ] **Step 3: Implement the kwarg**

Edit `cclikesh-debug/lib/cclikesh/debug/pty_runner.rb`:

Modify `initialize` (currently line 18-25) to accept the new kwarg with a default of `false`:

```ruby
      def initialize(argv:, cols:, rows:, env:, timeout_sec:, event_sink:, clear_size_env: false)
        @argv            = argv
        @cols            = cols
        @rows            = rows
        @env             = env
        @timeout_sec     = timeout_sec.to_f
        @event_sink      = event_sink
        @clear_size_env  = clear_size_env
      end
```

Modify `env_for_spawn` (currently line 55-60) to branch on the flag:

```ruby
      def env_for_spawn
        merged = ENV.to_h.merge(@env || {})
        if @clear_size_env
          merged.delete("COLUMNS")
          merged.delete("LINES")
        else
          merged["COLUMNS"] = @cols.to_s
          merged["LINES"]   = @rows.to_s
        end
        merged
      end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rake test TEST=test/cclikesh-debug/test_pty_runner.rb`
Expected: all PtyRunner tests pass, including the two new ones.

- [ ] **Step 5: Commit**

Stage `cclikesh-debug/lib/cclikesh/debug/pty_runner.rb` and `cclikesh-debug/test/cclikesh-debug/test_pty_runner.rb`. Commit:

`feat(pty_runner): add clear_size_env mode to spawn child without LINES/COLUMNS`

---

### Task 6: PtyRunner — `script_resize(cols, rows)` API

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/pty_runner.rb`
- Modify: `cclikesh-debug/test/cclikesh-debug/test_pty_runner.rb`

- [ ] **Step 1: Write the failing test**

Append to `TestPtyRunner`:

```ruby
  def test_script_resize_changes_pty_winsize_visible_to_child
    # Run a tiny shell loop that on SIGWINCH prints the new size via stty.
    # We use bash because POSIX `trap` + `stty size` reliably reports
    # SIGWINCH-driven dimensions on macOS.
    script = <<~BASH
      stty size
      trap 'stty size' WINCH
      sleep 0.5
      sleep 0.5
      sleep 0.5
    BASH
    @ev = []
    sink = ->(ts:, dir:, bytes:) { @ev << { ts: ts, dir: dir, bytes: bytes } }
    runner = Cclikesh::Debug::PtyRunner.new(
      argv:        ["/bin/bash", "-c", script],
      cols:        80,
      rows:        24,
      env:         {},
      timeout_sec: 4.0,
      event_sink:  sink,
    )
    runner.run do |sess|
      sess.wait 0.3   # let the initial `stty size` print 24 80
      sess.resize(120, 30)
      sess.wait 0.4   # let the trap fire and print the new size
    end
    output = @ev.select { |e| e[:dir] == "o" }.map { |e| e[:bytes] }.join.b
    # Initial line: "24 80" (rows cols), post-resize line: "30 120".
    # Both reported by `stty size` which prints "<rows> <cols>".
    assert_match(/24 80/, output, "initial size must be 24x80")
    assert_match(/30 120/, output, "post-resize size must be 30x120")
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rake test TEST=test/cclikesh-debug/test_pty_runner.rb`
Expected: failure — `NoMethodError: undefined method 'resize' for ScriptApi`.

- [ ] **Step 3: Implement the API**

Edit `cclikesh-debug/lib/cclikesh/debug/pty_runner.rb`:

In `class ScriptApi` (currently line 10-16), add `resize`:

```ruby
      class ScriptApi
        def initialize(runner)
          @runner = runner
        end
        def send(str);    @runner.script_send(str);          end
        def wait(seconds);@runner.script_wait(seconds.to_f); end
        def resize(cols, rows); @runner.script_resize(cols, rows); end
      end
```

In the `PtyRunner` class, add `script_resize` near the other `script_*` methods (after `script_wait`, around line 51):

```ruby
      def script_resize(cols, rows)
        # IO#winsize= takes [rows, cols] per io/console. Public arg order
        # mirrors PtyRunner.new(cols:, rows:) for consistency.
        @r.winsize = [rows, cols]
      rescue Errno::ENOTTY, IOError
        # Non-PTY masters (test stubs) cannot accept winsize; ignore.
        nil
      end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rake test TEST=test/cclikesh-debug/test_pty_runner.rb`
Expected: all tests, including the resize test, pass.

If `bash`'s `trap '...' WINCH` doesn't fire reliably under PTY, fall back to using `tcsh`/`zsh` or to a Ruby helper:

```ruby
script = "ruby -r io/console -e 'STDOUT.sync=true; trap(\"WINCH\"){p IO.console.winsize}; p IO.console.winsize; sleep 1.0'"
```

Adjust the assertions accordingly: `assert_match(/\[24, 80\]/, output)` and `assert_match(/\[30, 120\]/, output)`. The Ruby variant is more portable and easier to assert on.

- [ ] **Step 5: Commit**

Stage modified files. Commit:

`feat(pty_runner): add script_resize API to fire SIGWINCH from spec scripts`

---

### Task 7: SpecDSL forwards `clear_size_env:` + `resize` step + diag log; Captured exposes `diag_entries`

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/spec_dsl.rb`
- Modify: `cclikesh-debug/lib/cclikesh/debug/captured.rb`
- Modify: `cclikesh-debug/test/cclikesh-debug/test_spec_dsl.rb`

- [ ] **Step 1: Write the failing test**

Inspect existing `cclikesh-debug/test/cclikesh-debug/test_spec_dsl.rb` first (it likely uses an inline string spec via `SpecDSL.evaluate`). Append a new test that proves: (a) `clear_size_env: true` reaches the runner, (b) `resize` step fires, (c) diag log path is auto-injected and parsed into `captured.diag_entries`.

Add this test method to the existing `class TestSpecDSL` (look at the current file first to match its style and helpers):

```ruby
  def test_clear_size_env_resize_and_diag_entries_round_trip
    require "tmpdir"
    src = <<~SPEC
      session "diag round trip" do
        timeout 5
        spawn argv: ["/usr/bin/env", "ruby", "-r", "io/console", "-e",
                     "STDOUT.sync=true; trap('WINCH'){p IO.console.winsize; exit 0}; sleep 2"],
              cols: 80,
              rows: 24,
              clear_size_env: true
        wait 0.3
        resize 120, 30
        wait 0.5
      end

      expect "post-resize size visible in output" do |c|
        c.contains?("[30, 120]")
      end
    SPEC

    db_path = File.join(Dir.tmpdir, "spec-dsl-diag-#{Process.pid}-#{rand(1<<32).to_s(16)}.sqlite")
    result = Cclikesh::Debug::SpecDSL.evaluate(src, db_path: db_path, spec_path: "(test)")
    assert_equal 0, result.exit_status
    outcomes = Cclikesh::Debug::SpecDSL.dispatch_expects(result)
    assert outcomes.first[:pass], "expect should pass; got #{outcomes.inspect}"
    # diag_entries: the spawned ruby process never required cclikesh, so
    # diag log will be empty — but it must still be an Array (not nil).
    assert_kind_of Array, result.captured.diag_entries
  ensure
    File.unlink(db_path) if db_path && File.exist?(db_path)
  end
```

- [ ] **Step 2: Run to verify failure**

Run:
```
cd cclikesh-debug
bundle exec rake test TEST=test/cclikesh-debug/test_spec_dsl.rb
```
Expected: failure — `DslError: unknown keyword :clear_size_env` or `NoMethodError: undefined method 'resize' for SessionScope`.

- [ ] **Step 3: Implement DSL changes**

Edit `cclikesh-debug/lib/cclikesh/debug/spec_dsl.rb`:

Modify `SessionScope#spawn` (line 26-29) to accept `clear_size_env:`:

```ruby
        def spawn(argv:, cols:, rows:, env: {}, clear_size_env: false)
          raise DslError, "session: only one spawn per session" if @spawn_args
          @spawn_args = { argv: argv, cols: cols, rows: rows, env: env, clear_size_env: clear_size_env }
        end
```

Add a `resize` step method on `SessionScope` next to `wait` and `send`:

```ruby
        def resize(cols, rows); @steps << [:resize, cols.to_i, rows.to_i]; end
```

Modify `SpecDSL.run` (line 66-103) to:
1. Compute a per-session diag log path before spawn.
2. Inject `CCLIKESH_LAYOUT_DIAG=<path>` into the spawn env hash.
3. Forward `clear_size_env:` to `PtyRunner.new`.
4. Dispatch `:resize` step to `api.resize`.
5. Read+parse the diag log file post-run, pass entries into `Captured.from_storage`.
6. Clean up the diag log file.

Replace the body of `SpecDSL.run` with:

```ruby
      def self.run(top, db_path:, spec_path:)
        require "tmpdir"
        require "fileutils"
        scope = top.session_scope
        storage = PtyStorage.open(db_path)
        uuid = SecureRandom.uuid
        diag_path = File.join(Dir.tmpdir, "cclikesh-diag-#{uuid}.log")
        spawn_env = (scope.spawn_args[:env] || {}).merge("CCLIKESH_LAYOUT_DIAG" => diag_path)
        begin
          storage.insert_session(
            uuid: uuid, argv: scope.spawn_args[:argv],
            cols: scope.spawn_args[:cols], rows: scope.spawn_args[:rows],
            env:  spawn_env,
            spec_path: spec_path.to_s, timeout_sec: scope.timeout_sec
          )
          sink = ->(ts:, dir:, bytes:) {
            storage.insert_event(session_uuid: uuid, ts: ts, dir: dir, bytes: bytes)
          }
          runner = PtyRunner.new(
            argv: scope.spawn_args[:argv],
            cols: scope.spawn_args[:cols],
            rows: scope.spawn_args[:rows],
            env:  spawn_env,
            timeout_sec: scope.timeout_sec,
            event_sink: sink,
            clear_size_env: scope.spawn_args[:clear_size_env] || false,
          )
          status = runner.run do |api|
            scope.each_step do |kind, *payload|
              case kind
              when :wait   then api.wait(payload.first)
              when :send   then api.send(payload.first)
              when :resize then api.resize(payload[0], payload[1])
              end
            end
          end
          storage.mark_ended(uuid: uuid, exit_status: status)
          diag_entries = parse_diag_log(diag_path)
          captured = Captured.from_storage(storage, uuid, diag_entries: diag_entries)
          Result.new(session_uuid: uuid, exit_status: status,
                     captured: captured, expects: top.expects)
        ensure
          storage.close
          FileUtils.rm_f(diag_path)
        end
      end

      def self.parse_diag_log(path)
        return [] unless File.exist?(path)
        File.readlines(path).map { |line| parse_diag_line(line) }.compact
      end

      def self.parse_diag_line(line)
        # Format: [ISO8601] <tag> curses.lines=<v> curses.cols=<v> maxyx=<v> winsize=<v> env_lines=<v> env_cols=<v>
        m = line.match(/\A\[(?<ts>[^\]]+)\] (?<tag>\S+) curses\.lines=(?<lines>\S+) curses\.cols=(?<cols>\S+) maxyx=(?<maxyx>.*?) winsize=(?<winsize>.*?) env_lines=(?<env_lines>\S+) env_cols=(?<env_cols>\S+)\z/)
        return nil unless m
        {
          ts:        m[:ts],
          tag:       m[:tag],
          lines:     parse_diag_value(m[:lines]),
          cols:      parse_diag_value(m[:cols]),
          maxyx:     parse_diag_value(m[:maxyx]),
          winsize:   parse_diag_value(m[:winsize]),
          env_lines: parse_diag_value(m[:env_lines]),
          env_cols:  parse_diag_value(m[:env_cols]),
        }
      end

      # Parses Ruby `.inspect` output for the values produced by LayoutDiag:
      # nil, an Integer, an Array of Integers (or nil entries), or "..." quoted.
      def self.parse_diag_value(s)
        s = s.strip.chomp("\n")
        return nil if s == "nil"
        return Integer(s) if s.match?(/\A-?\d+\z/)
        if s.start_with?("[") && s.end_with?("]")
          inner = s[1..-2]
          return [] if inner.strip.empty?
          return inner.split(",").map { |x| parse_diag_value(x) }
        end
        if s.start_with?('"') && s.end_with?('"')
          return s[1..-2]
        end
        s
      end
```

Note: `each_step` currently yields `(kind, payload)` for two-element tuples. Confirm by reading the current `SessionScope#each_step` (line 36) — it does `@steps.each(&blk)`, so block receives the array. Existing call site does `do |kind, payload|` and Ruby destructures `[kind, payload]` to those names. The new `[kind, cols, rows]` triple destructures via `do |kind, *payload|` (changed in the snippet above). Verify existing two-element steps still dispatch correctly after this change: `payload.first` is `seconds` for `:wait` and the string for `:send`.

- [ ] **Step 4: Update `Captured.from_storage` and `initialize`**

Edit `cclikesh-debug/lib/cclikesh/debug/captured.rb`:

```ruby
      def self.from_storage(storage, uuid, diag_entries: [])
        info = storage.fetch_session(uuid)
        frames = storage.each_event(uuid).to_a
        new(uuid: uuid, info: info, frames: frames, diag_entries: diag_entries)
      end

      def initialize(uuid:, info:, frames:, diag_entries: [])
        @uuid          = uuid
        @info          = info
        @frames        = frames.freeze
        @diag_entries  = diag_entries.freeze
        # ...rest of pre-compute block unchanged...
        freeze
      end

      attr_reader :frames, :diag_entries
```

- [ ] **Step 5: Run to verify pass**

Run:
```
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/cclikesh-debug
bundle exec rake test TEST=test/cclikesh-debug/test_spec_dsl.rb
bundle exec rake test TEST=test/cclikesh-debug/test_pty_runner.rb
```
Expected: all green, including the new round-trip test.

Also re-run the existing PTY specs to ensure no regression. Each existing spec under `cclikesh-debug/test/specs/` still calls `spawn` without `clear_size_env:`, so the default `false` keeps prior behaviour. Verify:

```
bundle exec ruby exe/cclikesh-debug play test/specs/no_alt_screen.rb
bundle exec ruby exe/cclikesh-debug play test/specs/winsize_stale_env.rb
bundle exec ruby exe/cclikesh-debug play test/specs/pwd_output_in_body.rb
bundle exec ruby exe/cclikesh-debug play test/specs/layout_after_slash.rb
```

All should still PASS the same expectations they did before.

- [ ] **Step 6: Commit**

Stage modified files. Commit:

`feat(spec_dsl): forward clear_size_env, dispatch resize step, capture diag entries`

---

### Task 8: Spec R1 — `cmux_env_resize_cursor.rb` (cursor jumps after resize)

**Files:**
- Create: `cclikesh-debug/test/specs/cmux_env_resize_cursor.rb`

This task does NOT include a fix for R1 (that's out of scope per spec §5). It writes the regression spec; if the spec FAILS when run, the diag log + byte stream pinpoints the root cause. If it PASSES, the cmux-env hypothesis is invalidated and the next session pivots.

- [ ] **Step 1: Write the spec file**

```ruby
# cclikesh-debug/test/specs/cmux_env_resize_cursor.rb
#
# R1: After typing a slash command and resizing, the visible cursor lands
# inside the body text instead of on the prompt row. Reproduced under
# cmux-like env (LINES/COLUMNS unset in the child) by opting into
# clear_size_env: true and firing a real SIGWINCH via script_resize.

session "resize after slash command parks cursor on prompt row" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  80,
        rows:  24,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" },
        clear_size_env: true
  wait 1.5
  send "/heko\r"
  wait 0.8
  resize 80, 40
  wait 0.8
  send "\x03"   # Ctrl-C to clear the prompt buffer
  wait 0.3
  send "/q\r"
  wait 0.6
end

# The post-resize Chrome.handle_resize.after_resizeterm entry tells us the
# new curses.lines value. The prompt row is at lines - FOOTER_HEIGHT - 1
# (1-based, see Runner.park_cursor_on_prompt_row).
expect "post-resize handle_resize entry sees the new size" do |c|
  resize_entries = c.diag_entries.select { |e| e[:tag] == "Chrome.handle_resize.after_resizeterm" }
  !resize_entries.empty? && resize_entries.last[:lines] == 40 && resize_entries.last[:cols] == 80
end

expect "final cursor placement is on the prompt row" do |c|
  resize_entries = c.diag_entries.select { |e| e[:tag] == "Chrome.handle_resize.after_resizeterm" }
  next false if resize_entries.empty?
  final_lines = resize_entries.last[:lines]
  footer_h = 3  # mirrors Cclikesh::Chrome::FOOTER_HEIGHT
  expected_row = final_lines - footer_h - 1   # 1-based row from park_cursor_on_prompt_row

  cups = c.output_bytes.scan(/\e\[(\d+);(\d+)H/).map { |r, col| [r.to_i, col.to_i] }
  next false if cups.empty?
  final_cup = cups.last
  final_cup[0] == expected_row
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
```

- [ ] **Step 2: Run the spec**

Run:
```
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/cclikesh-debug
bundle exec ruby exe/cclikesh-debug play test/specs/cmux_env_resize_cursor.rb
```

Expected: one of two outcomes is acceptable per spec §7:
- (A) **All PASS** — R1 not reproducible in this env mode; record this finding for the follow-up handoff.
- (B) **`final cursor placement` FAILS** — R1 reproduced. The diag entries + final CUP value reveal the wrong row. Record the actual final CUP and the expected row in a follow-up handoff doc; the fix is out-of-scope for this plan.

If the spec ERRORS (unexpected exception, segfault, anything other than a clean PASS/FAIL of the expectations), debug as a real bug — that means the diag infrastructure or DSL wiring has a defect.

- [ ] **Step 3: Commit**

Stage `cclikesh-debug/test/specs/cmux_env_resize_cursor.rb`. Commit:

`test(debug): R1 spec — cursor must park on prompt row after resize in cmux-env`

---

### Task 9: Spec R2 — `cmux_env_slash_layout.rb` (vertical gap + footer disappearance)

**Files:**
- Create: `cclikesh-debug/test/specs/cmux_env_slash_layout.rb`

- [ ] **Step 1: Write the spec file**

```ruby
# cclikesh-debug/test/specs/cmux_env_slash_layout.rb
#
# R2: After /pwd or /heko, the body output is separated from the next
# prompt by many blank rows AND the 3-row footer (spinner / info_bar /
# shortcuts hint) disappears. Reproduced under cmux-like env (LINES/
# COLUMNS unset in the child) by opting into clear_size_env: true.

session "slash command output keeps footer visible and gap small" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  120,
        rows:  40,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" },
        clear_size_env: true
  wait 1.5
  send "/pwd\r"
  wait 0.8
  send "/heko\r"
  wait 0.8
  send "/q\r"
  wait 0.6
end

# Diag: every Display.refresh between /pwd and quit must report curses.lines
# matching the spawn rows (40), not a 24/80 default.
expect "Display.refresh sees the real winsize throughout" do |c|
  refresh_entries = c.diag_entries.select { |e| e[:tag] == "Display.refresh" }
  next false if refresh_entries.empty?
  max_lines = refresh_entries.map { |e| e[:lines] }.compact.max
  max_lines == 40
end

# Byte: the tail of the byte stream (last 4 KiB before /q echo) must
# contain a spinner glyph — proves the footer was painted in the final
# visible frame.
expect "spinner glyph present in final visible frame" do |c|
  bytes = c.output_bytes
  # Find the last "/q" the child echoed. Slice the 4 KiB before it.
  q_idx = bytes.rindex("/q")
  tail_start = q_idx ? [q_idx - 4096, 0].max : [bytes.bytesize - 4096, 0].max
  tail = bytes.byteslice(tail_start, [4096, bytes.bytesize - tail_start].min)
  tail.include?("*") || tail.include?("+")
end

# Byte: between the /heko body output and the last "> " prompt, the count
# of "\n" bytes must be <= 2. More than 2 indicates the large vertical gap
# symptom of R2.
expect "no large vertical gap between /heko output and next prompt" do |c|
  bytes = c.output_bytes
  marker = "Unknown command: /heko"
  m_idx = bytes.index(marker)
  next true unless m_idx   # if marker absent, /heko didn't reach Display — separate bug, don't false-positive R2
  prompt_idx = bytes.index("> ", m_idx + marker.length)
  next true unless prompt_idx
  span = bytes.byteslice(m_idx + marker.length, prompt_idx - (m_idx + marker.length))
  span.count("\n") <= 2
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
```

- [ ] **Step 2: Run the spec**

Run:
```
cd cclikesh-debug
bundle exec ruby exe/cclikesh-debug play test/specs/cmux_env_slash_layout.rb
```

Expected: PASS or FAIL — both are informative per spec §7.

If FAIL, capture which expectation failed and the relevant diag entries in a follow-up handoff.

- [ ] **Step 3: Commit**

Stage the new spec. Commit:

`test(debug): R2 spec — slash output keeps footer + small gap in cmux-env`

---

### Task 10: Spec R3 — `cmux_env_resize_divider.rb` (divider width follows resize)

**Files:**
- Create: `cclikesh-debug/test/specs/cmux_env_resize_divider.rb`

- [ ] **Step 1: Write the spec file**

```ruby
# cclikesh-debug/test/specs/cmux_env_resize_divider.rb
#
# R3: Resize does not reflow dividers to the new terminal width. Reproduced
# under cmux-like env by opting into clear_size_env: true and firing a real
# SIGWINCH via script_resize to a wider size.

session "resize widens dividers to match new cols" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  80,
        rows:  24,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" },
        clear_size_env: true
  wait 1.5
  send "\r"          # harmless input; ensures the read loop has run at least once
  wait 0.4
  resize 120, 30
  wait 0.8           # let SIGWINCH propagate + Chrome.handle_resize complete
  send "/q\r"
  wait 0.6
end

expect "post-resize Chrome.draw_dividers sees cols=120, lines=30" do |c|
  draw_entries = c.diag_entries.select { |e| e[:tag] == "Chrome.draw_dividers" }
  next false if draw_entries.empty?
  last = draw_entries.last
  last[:cols] == 120 && last[:lines] == 30
end

expect "Chrome.handle_resize.after_resizeterm winsize is [30, 120]" do |c|
  rs = c.diag_entries.select { |e| e[:tag] == "Chrome.handle_resize.after_resizeterm" }
  next false if rs.empty?
  rs.last[:winsize] == [30, 120]
end

# Byte: locate the divider redraw after resize. The divider is drawn via
# ACS_HLINE (A_ALTCHARSET | 0x71). On stock xterm-style terminfo, ncurses
# brackets the run with SO/SI (\e(0 ... \e(B). We accept either bracketed
# or unbracketed forms by counting the 'q' bytes in the run after stripping
# the optional SO/SI brackets.
expect "divider after resize spans the new cols (120 cells, not 80)" do |c|
  resize_entries = c.diag_entries.select { |e| e[:tag] == "Chrome.handle_resize.after_resizeterm" }
  next false if resize_entries.empty?
  post_resize_lines = resize_entries.last[:lines]
  divider_row_top    = post_resize_lines - 3 - 3  # lines - FOOTER_HEIGHT - 3, 0-based
  divider_row_bottom = post_resize_lines - 3 - 1  # lines - FOOTER_HEIGHT - 1, 0-based
  # Convert to 1-based for the CUP we're searching for.
  candidates = [divider_row_top + 1, divider_row_bottom + 1]

  bytes = c.output_bytes
  # Search from the byte index of the last resize log entry forward. We
  # don't have byte indices for diag entries, so use a simple heuristic:
  # the LAST CUP-to-divider-row plus the next 200 bytes is the divider draw.
  found_widths = []
  candidates.each do |row|
    cup_pattern = "\e[#{row};1H".b
    last_cup = bytes.b.rindex(cup_pattern)
    next unless last_cup
    slice = bytes.byteslice(last_cup + cup_pattern.bytesize, 400)
    # Strip optional leading SO and trailing SI.
    slice = slice.sub(/\A\e\(0/, "")
    # Stop at the first non-q byte AFTER the run (or at SI).
    run = slice[/\Aq+/] || ""
    found_widths << run.length
  end
  found_widths.any? { |w| w == 120 } && !found_widths.any? { |w| w == 80 }
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
```

- [ ] **Step 2: Run the spec**

Run:
```
cd cclikesh-debug
bundle exec ruby exe/cclikesh-debug play test/specs/cmux_env_resize_divider.rb
```

Expected: PASS or FAIL — both informative.

If the byte-level `divider after resize spans the new cols` expectation fails, the most likely cause is that the byte form of the divider differs from the assumed `\e(0qqq...\e(B`. Inspect `c.output_bytes` near the post-resize CUP to see the actual encoding. Update the assertion's regex to match what's actually there before claiming R3 is reproduced. (The diag-entry assertions remain the source of truth for whether ncurses saw the right size.)

- [ ] **Step 3: Commit**

Stage the new spec. Commit:

`test(debug): R3 spec — divider width follows resize in cmux-env`

---

### Task 11: Full-suite run + handoff doc

- [ ] **Step 1: Run the full root test suite**

Delegate to a `general-purpose` subagent (per `~/dev/src/CLAUDE.md` "Test Execution Delegation"):

> Working dir: /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell. Run `bundle exec rake test`. Report only pass/fail counts and total. If any failures, list the failing test names. Under 100 words.

Expected: prior 171 / 0 / 0 + the new tests added in Tasks 1–4 (5+2+2+1 = 10 new). Anticipate `181 / 0 / 0` (or close, depending on whether the existing `test_echo_shell_boots_and_quits_cleanly` 15s-timeout pre-existing flake fires this run — `feedback_verify_before_handoff.md`/`memory/project_echo_shell_smoke_timeout.md`).

If new failures: investigate before continuing. Do NOT mark task complete.

- [ ] **Step 2: Run the cclikesh-debug suite**

Delegate to subagent:

> Working dir: /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/cclikesh-debug. Run `bundle exec rake test`. Report only pass/fail counts. Under 80 words.

Expected: prior 63 / 0 / 0 + Tasks 5–7's new tests (2+1+1 = 4 new). Anticipate ~67 / 0 / 0.

- [ ] **Step 3: Run the three new R1/R2/R3 specs and capture results**

Each is run via the play CLI:

```
cd cclikesh-debug
bundle exec ruby exe/cclikesh-debug play test/specs/cmux_env_resize_cursor.rb
bundle exec ruby exe/cclikesh-debug play test/specs/cmux_env_slash_layout.rb
bundle exec ruby exe/cclikesh-debug play test/specs/cmux_env_resize_divider.rb
```

For EACH, record:
- Which expectations PASSed and which FAILed.
- For each FAILed expectation, copy the relevant diag entries (filter `c.diag_entries` by tag in a one-liner script if needed) and the relevant byte slice.

These results are the actual diagnostic output of this whole plan.

- [ ] **Step 4: Write the handoff doc with findings**

Create `docs/superpowers/handoff/2026-05-15-curses-noalt-diag-results.md`. Structure:

```markdown
# Curses Noalt Diagnostic Strategy — Results

**Date:** 2026-05-15
**Predecessor plan:** docs/superpowers/plans/2026-05-15-curses-noalt-diag-strategy.md
**Predecessor handoff:** docs/superpowers/handoff/2026-05-15-curses-noalt-residual-bugs.md

## Test suite status
- root rake test: <pass>/<fail>/<error>
- cclikesh-debug rake test: <pass>/<fail>/<error>

## R1 spec results (cmux_env_resize_cursor.rb)
- post-resize handle_resize entry sees new size: PASS/FAIL
- final cursor placement is on prompt row: PASS/FAIL
- session exits cleanly: PASS/FAIL

(If FAIL): final CUP was [<row>, <col>], expected row <N>. Diag entries:
  ```
  <paste relevant diag lines>
  ```

## R2 spec results (cmux_env_slash_layout.rb)
[same shape]

## R3 spec results (cmux_env_resize_divider.rb)
[same shape]

## Diagnosis (which of theories e–j the data supports)

[Cross-reference handoff doc theories e–j; e.g. "Theory (e) confirmed: Display.refresh diag shows curses.lines=24 even though spawn rows=40" — or — "All Curses values correct; bug must be downstream of curses' size detection (theories f, h, i remain candidates)"]

## Recommended next-session focus

[Short list — one-paragraph guidance for the next session that will write the actual fix]
```

- [ ] **Step 5: Commit handoff doc**

Stage `docs/superpowers/handoff/2026-05-15-curses-noalt-diag-results.md`. Commit:

`docs(handoff): diagnostic results from curses noalt diag strategy run`

(`docs/superpowers` is gitignored — use `git add -f` as the existing workflow does.)

- [ ] **Step 6: Final report to user**

Plain-text summary in the chat (NOT a new file):
- Suite status (root + debug counts)
- One line per R-spec: which expectations passed/failed
- Recommended next focus area

---

## Notes for the implementing agent

- **Discipline:** This codebase has a documented 4-time violation of `feedback_verify_before_handoff.md`. The whole point of this plan is to make the verification path TRUSTABLE. Do NOT mark Task 11 complete unless you have actually run all three R-specs and captured their results. Do NOT skip the handoff doc.
- **Git via subagent:** All git operations go through a `general-purpose` subagent per `~/.claude/CLAUDE.md`. Do not run `git diff`/`git status`/`git log` inline — context cost.
- **No silent rescues outside `LayoutDiag`:** Per `~/dev/src/CLAUDE.md`, `rescue StandardError; nil` is permitted ONLY inside `LayoutDiag.log` because the contract is explicit (debug-only, must never affect production). All other code paths must propagate, log, or re-raise.
- **`docs/superpowers` is gitignored** — every commit that touches a file under it needs `git add -f`.
- **Existing pre-existing flake:** `test_echo_shell_boots_and_quits_cleanly` may sporadically time out (15 s); per `memory/project_echo_shell_smoke_timeout.md` this predates this plan and is not a regression. If it fires, note it in the report but do not block on it.
