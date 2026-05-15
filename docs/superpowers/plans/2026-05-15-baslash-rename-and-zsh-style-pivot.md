# baslash rename + zsh-style + title-bar pivot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `cclikesh` to `baslash`, drop curses entirely, pivot the visual model from "fixed footer + sub-region body" to "natural-flow zsh-style + terminal title bar status".

**Architecture:** Body content is `puts`'d to stdout (natural scroll → terminal scrollback). Status (cwd, var count, phase, spinner) goes to the terminal title bar via OSC 0/2. Reline owns prompt + input editing + history + dialog procs (slash menu / ghost text). Slash subsystem (registry / dispatcher / HandlerRactor) and Builder DSL are carried over with namespace rename only.

**Tech Stack:** Ruby 4.x (CRuby), Reline 0.6 (CRuby bundled), test-unit 3.6, extralite 2.x (debug harness only). No curses dependency. macOS + Terminal.app + cmux only.

**Spec:** `docs/superpowers/specs/2026-05-15-baslash-rename-and-zsh-style-pivot-design.md`

---

## File Structure (post-implementation)

```
baslash.gemspec                   # was: cclikesh.gemspec
Gemfile                           # updated: drop curses, point at baslash-debug
lib/baslash.rb                    # was: lib/cclikesh.rb
lib/baslash/version.rb
lib/baslash/style.rb              # rewritten: SGR strings, no curses
lib/baslash/title_bar.rb          # NEW: OSC 0/2 set/restore + spinner
lib/baslash/transcript.rb         # ported
lib/baslash/context.rb            # ported
lib/baslash/main_ctx.rb           # ported
lib/baslash/display.rb            # rewritten: puts + \r\e[K live slots
lib/baslash/shareable_ref.rb      # ported
lib/baslash/slash_registry.rb     # ported
lib/baslash/ctx_proxy.rb          # ported
lib/baslash/handler_ractor.rb     # ported
lib/baslash/slash_dispatcher.rb   # ported
lib/baslash/reline_dialogs.rb     # ported + simplified (drop chrome tick)
lib/baslash/builder.rb            # ported
lib/baslash/default_commands.rb   # ported
lib/baslash/debug_commands.rb     # ported
lib/baslash/debug_endpoint.rb     # ported
lib/baslash/runner.rb             # rewritten: slim, no curses

baslash-debug/                    # was: cclikesh-debug/
baslash-debug/exe/baslash-debug
baslash-debug/baslash-debug.gemspec
baslash-debug/lib/baslash/debug/*.rb
baslash-debug/test/baslash-debug/*.rb
baslash-debug/test/specs/*.rb

test/test_*.rb                    # ported tests with namespace renamed
test/test_helper.rb
test/test_title_bar.rb            # NEW

examples/echo_shell.rb            # updated: Baslash.run
examples/zsh_shell/*              # updated: Baslash.run
examples/irb_shell/*              # updated: Baslash.run

# DELETED
lib/cclikesh.rb
lib/cclikesh/                     # entire tree
cclikesh.gemspec
cclikesh-debug/                   # entire tree (after rename to baslash-debug)
test/test_chrome.rb
test/test_chrome_layout_diag.rb
test/test_terminfo_overlay.rb
test/test_layout_diag.rb
test/test_display_layout_diag.rb
test/test_runner_layout_diag.rb
test/test_curses_integration.rb
```

---

## Task 1: Bootstrap baslash gem skeleton

**Files:**
- Create: `baslash.gemspec`
- Create: `lib/baslash.rb`
- Create: `lib/baslash/version.rb`
- Modify: `Gemfile` (drop curses, gemspec name change inherited)
- Modify: `Rakefile` (no change expected; verify)

- [ ] **Step 1: Write the failing test**

`test/test_baslash_gem.rb`:
```ruby
require "test/unit"

class TestBaslashGem < Test::Unit::TestCase
  def test_baslash_module_loads
    require "baslash"
    assert defined?(Baslash)
    assert defined?(Baslash::VERSION)
    assert_match(/\A\d+\.\d+\.\d+\z/, Baslash::VERSION)
  end

  def test_baslash_run_signature
    require "baslash"
    assert_respond_to Baslash, :run
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec ruby -Ilib -Itest test/test_baslash_gem.rb
```

Expected: `LoadError: cannot load such file -- baslash`

- [ ] **Step 3: Write minimal implementation**

`lib/baslash/version.rb`:
```ruby
# frozen_string_literal: true

module Baslash
  VERSION = "0.3.0"
end
```

`lib/baslash.rb`:
```ruby
# frozen_string_literal: true

require_relative "baslash/version"

module Baslash
  def self.run(&block)
    raise NotImplementedError, "Baslash.run is wired in Task 10 (Runner)"
  end
end
```

`baslash.gemspec`:
```ruby
# frozen_string_literal: true

require_relative "lib/baslash/version"

Gem::Specification.new do |spec|
  spec.name          = "baslash"
  spec.version       = Baslash::VERSION
  spec.authors       = ["bash0C7"]
  spec.summary       = "Slash-command-driven Ruby framework for embedded interactive shell DSLs"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "reline",                "~> 0.6"
  spec.add_dependency "unicode-display_width", "~> 3.0"
  spec.add_dependency "logger"

  spec.add_development_dependency "test-unit", "~> 3.6"
  spec.add_development_dependency "rake",      "~> 13.0"
  spec.add_development_dependency "irb",       "~> 1.18"
end
```

`Gemfile`: replace existing content with:
```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "drb"
gem "rinda"

gem "informers", "~> 1.2"
gem "unicode-display_width", "~> 3.0"

group :development do
  gem "baslash-debug", path: "baslash-debug"
  gem "extralite", "~> 2.12"
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bundle install --local 2>/dev/null || bundle install
bundle exec ruby -Ilib -Itest test/test_baslash_gem.rb
```

Expected: `2 tests, 3 assertions, 0 failures, 0 errors`

NOTE: `bundle install` may fail because `baslash-debug` does not exist yet. If it does, temporarily comment out the `baslash-debug` line in the Gemfile, install, run the test, then restore the line.

- [ ] **Step 5: Commit**

```bash
git add baslash.gemspec lib/baslash.rb lib/baslash/version.rb Gemfile test/test_baslash_gem.rb
git commit -m "feat(baslash): bootstrap gem skeleton with version + Baslash.run stub"
```

---

## Task 2: Style module (SGR strings)

**Files:**
- Create: `lib/baslash/style.rb`
- Create: `test/test_style.rb` (replace existing)

- [ ] **Step 1: Write the failing test**

`test/test_style.rb`:
```ruby
require "test/unit"
require "baslash/style"

class TestStyle < Test::Unit::TestCase
  def test_bold_wraps_with_sgr
    assert_equal "\e[1mhi\e[0m", Baslash::Style.bold("hi")
  end

  def test_dim_wraps_with_sgr
    assert_equal "\e[2mhi\e[0m", Baslash::Style.dim("hi")
  end

  def test_color_wraps_with_named_color
    assert_equal "\e[31mhi\e[0m", Baslash::Style.color(:red, "hi")
    assert_equal "\e[32mhi\e[0m", Baslash::Style.color(:green, "hi")
  end

  def test_apply_named_style
    assert_equal "\e[1mhi\e[0m", Baslash::Style.apply(:bold, "hi")
    assert_equal "hi", Baslash::Style.apply(nil, "hi")
    assert_equal "hi", Baslash::Style.apply(:unknown, "hi")
  end

  def test_strip_removes_sgr_escapes
    assert_equal "hi", Baslash::Style.strip("\e[1mhi\e[0m")
    assert_equal "ab", Baslash::Style.strip("\e[31ma\e[0m\e[32mb\e[0m")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec ruby -Ilib -Itest test/test_style.rb
```

Expected: `LoadError: cannot load such file -- baslash/style`

- [ ] **Step 3: Write minimal implementation**

`lib/baslash/style.rb`:
```ruby
# frozen_string_literal: true

module Baslash
  module Style
    NAMED_COLORS = {
      black:   30, red:     31, green:   32, yellow:  33,
      blue:    34, magenta: 35, cyan:    36, white:   37
    }.freeze

    NAMED_STYLES = {
      bold:      1,
      dim:       2,
      italic:    3,
      underline: 4,
      reverse:   7
    }.freeze

    def self.bold(text);     wrap(NAMED_STYLES[:bold],      text); end
    def self.dim(text);      wrap(NAMED_STYLES[:dim],       text); end
    def self.italic(text);   wrap(NAMED_STYLES[:italic],    text); end
    def self.underline(text); wrap(NAMED_STYLES[:underline], text); end

    def self.color(name, text)
      code = NAMED_COLORS[name]
      return text.to_s if code.nil?
      wrap(code, text)
    end

    def self.apply(name, text)
      return text.to_s if name.nil?
      code = NAMED_STYLES[name] || NAMED_COLORS[name]
      return text.to_s if code.nil?
      wrap(code, text)
    end

    def self.strip(text)
      text.to_s.gsub(/\e\[[0-9;]*m/, "")
    end

    def self.wrap(code, text)
      "\e[#{code}m#{text}\e[0m"
    end
    private_class_method :wrap
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bundle exec ruby -Ilib -Itest test/test_style.rb
```

Expected: `5 tests, 11 assertions, 0 failures, 0 errors`

- [ ] **Step 5: Commit**

```bash
git add lib/baslash/style.rb test/test_style.rb
git commit -m "feat(baslash): Style module with SGR helpers (bold/dim/color/apply/strip)"
```

---

## Task 3: TitleBar module (OSC 0/2 + spinner)

**Files:**
- Create: `lib/baslash/title_bar.rb`
- Create: `test/test_title_bar.rb`

- [ ] **Step 1: Write the failing test**

`test/test_title_bar.rb`:
```ruby
require "test/unit"
require "stringio"
require "baslash/title_bar"

class TestTitleBar < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::TitleBar.reset_for_test
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_set_emits_osc0_sequence
    Baslash::TitleBar.set("hello")
    assert_equal "\e]0;hello\a", $stdout.string
  end

  def test_set_strips_unsafe_bytes
    Baslash::TitleBar.set("a\ab\ec")
    assert_equal "\e]0;abc\a", $stdout.string
  end

  def test_restore_emits_empty_title
    Baslash::TitleBar.restore
    assert_equal "\e]0;\a", $stdout.string
  end

  def test_tick_ready_uses_static_glyph
    Baslash::TitleBar.tick(phase: :ready, ctx_text: "ready text")
    assert_match(/\A\e\]0;✻ ready text\a\z/, $stdout.string)
  end

  def test_tick_working_advances_spinner
    Baslash::TitleBar.tick(phase: :working, ctx_text: "x")
    first = $stdout.string.dup
    $stdout.truncate(0); $stdout.rewind
    Baslash::TitleBar.tick(phase: :working, ctx_text: "x")
    second = $stdout.string
    refute_equal first, second, "spinner glyph should advance between ticks while working"
  end

  def test_tick_count_increments
    initial = Baslash::TitleBar.tick_count
    Baslash::TitleBar.tick(phase: :ready, ctx_text: "a")
    assert_equal initial + 1, Baslash::TitleBar.tick_count
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec ruby -Ilib -Itest test/test_title_bar.rb
```

Expected: `LoadError: cannot load such file -- baslash/title_bar`

- [ ] **Step 3: Write minimal implementation**

`lib/baslash/title_bar.rb`:
```ruby
# frozen_string_literal: true

module Baslash
  # Sets the terminal window title via OSC 0 escape sequences. Used to
  # surface ephemeral status (phase, cwd, var count, spinner) without
  # consuming on-screen real estate. macOS Terminal.app honors OSC 0;
  # cmux passes the sequence through transparently.
  module TitleBar
    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
    READY_GLYPH    = "✻"

    @frame      = 0
    @tick_count = 0
    @last_phase = :ready

    class << self
      attr_reader :tick_count
      attr_reader :last_phase

      def set(text)
        safe = text.to_s.gsub(/[\a\e]/, "")
        $stdout.print("\e]0;#{safe}\a")
        $stdout.flush
      end

      def restore
        $stdout.print("\e]0;\a")
        $stdout.flush
      end

      def tick(phase:, ctx_text:)
        @tick_count += 1
        @last_phase = phase
        glyph = phase == :working ? next_spinner_frame : READY_GLYPH
        text = ctx_text.to_s.empty? ? glyph : "#{glyph} #{ctx_text}"
        set(text)
      end

      def reset_for_test
        @frame      = 0
        @tick_count = 0
        @last_phase = :ready
      end

      private

      def next_spinner_frame
        f = SPINNER_FRAMES[@frame % SPINNER_FRAMES.size]
        @frame += 1
        f
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bundle exec ruby -Ilib -Itest test/test_title_bar.rb
```

Expected: `6 tests, 8 assertions, 0 failures, 0 errors`

- [ ] **Step 5: Commit**

```bash
git add lib/baslash/title_bar.rb test/test_title_bar.rb
git commit -m "feat(baslash): TitleBar module with OSC 0 set/restore + spinner tick"
```

---

## Task 4: Display module (puts + live slots)

**Files:**
- Create: `lib/baslash/display.rb`
- Create: `test/test_display.rb` (replace existing)

- [ ] **Step 1: Write the failing test**

`test/test_display.rb`:
```ruby
require "test/unit"
require "stringio"
require "baslash/display"

class TestDisplay < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::Display.reset_for_test
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_append_writes_line_with_newline
    Baslash::Display.append("hello")
    assert_equal "hello\n", $stdout.string
  end

  def test_append_with_style_wraps_in_sgr
    Baslash::Display.append("hi", style: :bold)
    assert_equal "\e[1mhi\e[0m\n", $stdout.string
  end

  def test_append_records_transcript
    require "baslash/transcript"
    Baslash::Transcript.reset_for_test if Baslash::Transcript.respond_to?(:reset_for_test)
    Baslash::Display.append("hi")
    assert Baslash::Transcript.lines.include?("hi"), "transcript should capture appended line"
  end if defined?(Baslash::Transcript)

  def test_open_live_returns_unique_sid
    sid1 = Baslash::Display.open_live
    sid2 = Baslash::Display.open_live
    refute_equal sid1, sid2
  end

  def test_live_update_emits_cr_clear_text
    sid = Baslash::Display.open_live
    $stdout.truncate(0); $stdout.rewind
    Baslash::Display.live_update(sid, "first")
    assert_equal "\r\e[K\e[1G\e[0mfirst\e[0m", $stdout.string
  end

  def test_live_commit_finalizes_with_newline
    sid = Baslash::Display.open_live
    Baslash::Display.live_update(sid, "intermediate")
    $stdout.truncate(0); $stdout.rewind
    Baslash::Display.live_commit(sid, "final value")
    assert_equal "\r\e[K\e[1G\e[0mfinal value\e[0m\n", $stdout.string
  end

  def test_live_discard_emits_cr_clear_no_newline
    sid = Baslash::Display.open_live
    Baslash::Display.live_update(sid, "anything")
    $stdout.truncate(0); $stdout.rewind
    Baslash::Display.live_discard(sid)
    assert_equal "\r\e[K", $stdout.string
  end

  def test_dialog_renders_box
    Baslash::Display.dialog("hello\nworld")
    out = $stdout.string
    assert_match(/┌─+┐/, out)
    assert_match(/│ hello/, out)
    assert_match(/│ world/, out)
    assert_match(/└─+┘/, out)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec ruby -Ilib -Itest test/test_display.rb
```

Expected: `LoadError: cannot load such file -- baslash/display`

- [ ] **Step 3: Write minimal implementation**

`lib/baslash/display.rb`:
```ruby
# frozen_string_literal: true

require "unicode/display_width"
require_relative "style"
require_relative "transcript"

module Baslash
  # Body content renderer. Writes lines directly to stdout so that the
  # terminal's natural scroll moves old rows into native scrollback.
  # Live slots are single-line in-place updates via CR + EL (\r\e[K) and
  # do not consume scrollback until committed.
  module Display
    @next_sid = 0
    @live_open = {}.compare_by_identity # sid (Integer) keys

    class << self
      def append(text, style: nil)
        line = Style.apply(style, text)
        $stdout.puts(line)
        $stdout.flush
        Transcript.record(text.to_s) if defined?(Baslash::Transcript)
      end

      def open_live(style: nil)
        sid = (@next_sid += 1)
        @live_open[sid] = { style: style, last: "" }
        sid
      end

      def live_update(sid, text)
        slot = @live_open[sid] or return
        slot[:last] = text.to_s
        $stdout.print("\r\e[K\e[1G")
        $stdout.print(Style.apply(slot[:style], text))
        $stdout.flush
      end

      def live_commit(sid, final = nil)
        slot = @live_open.delete(sid) or return
        text = (final.nil? ? slot[:last] : final).to_s
        $stdout.print("\r\e[K\e[1G")
        $stdout.print(Style.apply(slot[:style], text))
        $stdout.puts
        $stdout.flush
        Transcript.record(text) if defined?(Baslash::Transcript)
      end

      def live_discard(sid)
        @live_open.delete(sid)
        $stdout.print("\r\e[K")
        $stdout.flush
      end

      def dialog(content, style: nil)
        lines = content.to_s.split("\n", -1)
        lines.pop if lines.last == ""
        width = (lines.map { |l| Unicode::DisplayWidth.of(l) }.max || 0) + 2
        append("┌#{"─" * width}┐", style: :dim)
        lines.each do |line|
          pad_n = [width - 2 - Unicode::DisplayWidth.of(line), 0].max
          append("│ #{line}#{" " * pad_n} │", style: style)
        end
        append("└#{"─" * width}┘", style: :dim)
      end

      def reset_for_test
        @next_sid = 0
        @live_open.clear
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

This test depends on Transcript (Task 5). Skip the transcript-related test for now if Transcript doesn't exist:

```bash
bundle exec ruby -Ilib -Itest test/test_display.rb
```

Expected: most tests PASS; one may be skipped if Transcript not loaded yet. Total at least 7/7 PASS for the non-Transcript tests.

- [ ] **Step 5: Commit**

```bash
git add lib/baslash/display.rb test/test_display.rb
git commit -m "feat(baslash): Display module — puts-based body, CR/EL live slots, boxed dialog"
```

---

## Task 5: Port Context, ShareableRef, Transcript

**Files:**
- Create: `lib/baslash/context.rb` (port from `lib/cclikesh/context.rb`)
- Create: `lib/baslash/shareable_ref.rb` (port from `lib/cclikesh/shareable_ref.rb`)
- Create: `lib/baslash/transcript.rb` (port from `lib/cclikesh/transcript.rb`)
- Create: `test/test_context_baslash.rb` (port from `test/test_context.rb`)
- Create: `test/test_shareable_ref_baslash.rb` (port from `test/test_shareable_ref.rb`)
- Create: `test/test_transcript_baslash.rb` (NEW — Transcript currently has no test)

- [ ] **Step 1: Move test files with namespace renamed (failing tests)**

```bash
cp test/test_context.rb test/test_context_baslash.rb
sed -i '' 's/Cclikesh::Context/Baslash::Context/g; s/cclikesh\/context/baslash\/context/g' test/test_context_baslash.rb

cp test/test_shareable_ref.rb test/test_shareable_ref_baslash.rb
sed -i '' 's/Cclikesh::ShareableRef/Baslash::ShareableRef/g; s/cclikesh\/shareable_ref/baslash\/shareable_ref/g' test/test_shareable_ref_baslash.rb
```

Create `test/test_transcript_baslash.rb`:
```ruby
require "test/unit"
require "baslash/transcript"

class TestTranscriptBaslash < Test::Unit::TestCase
  def setup
    Baslash::Transcript.reset_for_test if Baslash::Transcript.respond_to?(:reset_for_test)
  end

  def test_record_appends_line
    Baslash::Transcript.record("hello")
    assert Baslash::Transcript.lines.include?("hello")
  end

  def test_lines_returns_array
    assert_kind_of Array, Baslash::Transcript.lines
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec ruby -Ilib -Itest test/test_context_baslash.rb
bundle exec ruby -Ilib -Itest test/test_shareable_ref_baslash.rb
bundle exec ruby -Ilib -Itest test/test_transcript_baslash.rb
```

Expected: each fails with `LoadError: cannot load such file -- baslash/<name>`.

- [ ] **Step 3: Port implementations**

```bash
cp lib/cclikesh/context.rb       lib/baslash/context.rb
cp lib/cclikesh/shareable_ref.rb lib/baslash/shareable_ref.rb
cp lib/cclikesh/transcript.rb    lib/baslash/transcript.rb

# Rename namespace inside the new files
sed -i '' 's/module Cclikesh/module Baslash/g; s/Cclikesh::/Baslash::/g; s/require_relative "cclikesh/require_relative "baslash/g' \
  lib/baslash/context.rb lib/baslash/shareable_ref.rb lib/baslash/transcript.rb
```

Check whether the original `lib/cclikesh/transcript.rb` defined `reset_for_test`:

```bash
grep -c "reset_for_test" lib/cclikesh/transcript.rb
```

If the count is `0`, the new test depends on a method the original lacked.
Add this method to `lib/baslash/transcript.rb`, near the top of the module body:

```ruby
def self.reset_for_test
  @lines = []
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/test_context_baslash.rb
bundle exec ruby -Ilib -Itest test/test_shareable_ref_baslash.rb
bundle exec ruby -Ilib -Itest test/test_transcript_baslash.rb
```

Expected: ALL PASS. Test counts should match the original `cclikesh` versions.

- [ ] **Step 5: Commit**

```bash
git add lib/baslash/context.rb lib/baslash/shareable_ref.rb lib/baslash/transcript.rb \
        test/test_context_baslash.rb test/test_shareable_ref_baslash.rb test/test_transcript_baslash.rb
git commit -m "feat(baslash): port Context + ShareableRef + Transcript"
```

---

## Task 6: Port SlashRegistry, SlashDispatcher, HandlerRactor

**Files:**
- Create: `lib/baslash/slash_registry.rb` (port)
- Create: `lib/baslash/slash_dispatcher.rb` (port)
- Create: `lib/baslash/handler_ractor.rb` (port)
- Create: `test/test_slash_registry_baslash.rb` (port)
- Create: `test/test_slash_dispatcher_baslash.rb` (port)
- Create: `test/test_handler_ractor_baslash.rb` (port)

- [ ] **Step 1: Move test files with namespace renamed**

```bash
for name in slash_registry slash_dispatcher handler_ractor; do
  cp test/test_${name}.rb test/test_${name}_baslash.rb
  sed -i '' 's/Cclikesh::/Baslash::/g; s/cclikesh\//baslash\//g' test/test_${name}_baslash.rb
done
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec ruby -Ilib -Itest test/test_slash_registry_baslash.rb
bundle exec ruby -Ilib -Itest test/test_slash_dispatcher_baslash.rb
bundle exec ruby -Ilib -Itest test/test_handler_ractor_baslash.rb
```

Expected: each fails with `LoadError`.

- [ ] **Step 3: Port implementations**

```bash
for name in slash_registry slash_dispatcher handler_ractor; do
  cp lib/cclikesh/${name}.rb lib/baslash/${name}.rb
  sed -i '' 's/module Cclikesh/module Baslash/g; s/Cclikesh::/Baslash::/g; s/require_relative "cclikesh/require_relative "baslash/g' \
    lib/baslash/${name}.rb
done
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/test_slash_registry_baslash.rb
bundle exec ruby -Ilib -Itest test/test_slash_dispatcher_baslash.rb
bundle exec ruby -Ilib -Itest test/test_handler_ractor_baslash.rb
```

Expected: ALL PASS at the original cclikesh test count.

- [ ] **Step 5: Commit**

```bash
git add lib/baslash/slash_registry.rb lib/baslash/slash_dispatcher.rb lib/baslash/handler_ractor.rb \
        test/test_slash_registry_baslash.rb test/test_slash_dispatcher_baslash.rb test/test_handler_ractor_baslash.rb
git commit -m "feat(baslash): port slash subsystem (registry / dispatcher / handler ractor)"
```

---

## Task 7: Port MainCtx, CtxProxy, Builder

**Files:**
- Create: `lib/baslash/main_ctx.rb` (port)
- Create: `lib/baslash/ctx_proxy.rb` (port)
- Create: `lib/baslash/builder.rb` (port)
- Create: `test/test_main_ctx_baslash.rb` (port)
- Create: `test/test_ctx_proxy_baslash.rb` (port)
- Create: `test/test_builder_baslash.rb` (port)

- [ ] **Step 1: Move test files with namespace renamed**

```bash
for name in main_ctx ctx_proxy builder; do
  cp test/test_${name}.rb test/test_${name}_baslash.rb
  sed -i '' 's/Cclikesh::/Baslash::/g; s/cclikesh\//baslash\//g' test/test_${name}_baslash.rb
done
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec ruby -Ilib -Itest test/test_main_ctx_baslash.rb
bundle exec ruby -Ilib -Itest test/test_ctx_proxy_baslash.rb
bundle exec ruby -Ilib -Itest test/test_builder_baslash.rb
```

Expected: each fails with `LoadError`.

- [ ] **Step 3: Port implementations**

```bash
for name in main_ctx ctx_proxy builder; do
  cp lib/cclikesh/${name}.rb lib/baslash/${name}.rb
  sed -i '' 's/module Cclikesh/module Baslash/g; s/Cclikesh::/Baslash::/g; s/require_relative "cclikesh/require_relative "baslash/g' \
    lib/baslash/${name}.rb
done
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/test_main_ctx_baslash.rb
bundle exec ruby -Ilib -Itest test/test_ctx_proxy_baslash.rb
bundle exec ruby -Ilib -Itest test/test_builder_baslash.rb
```

Expected: ALL PASS.

- [ ] **Step 5: Builder cleanup (per spec section 6.4)**

Inspect `lib/baslash/builder.rb` for the following:

1. If both `header_config` and `header_lines` exist as separate public DSL
   entry points: consolidate into `header_lines` (drop `header_config`,
   merge any unique fields it carried into the `header_lines` model).
2. The `evaluate_info_bar(main_ctx)` and `evaluate_status_rows(main_ctx)`
   methods are called from internal modules (`RelineDialogs`, `Runner`) —
   leave them as public methods documented as internal. (The spec's
   "make private" goal is deferred since making them private requires
   either `send(:_evaluate_*)` calls or a different module structure;
   tracked as follow-up after the v1 ship.)

If a consolidation is performed, add a focused test that the merged DSL
preserves the prior data flow:

```ruby
# add to test/test_builder_baslash.rb
def test_header_lines_carries_consolidated_fields
  b = Baslash::Builder.new
  b.header_lines ["banner1", "banner2"]
  assert_equal ["banner1", "banner2"], b.header_lines
end
```

Run the test:
```bash
bundle exec ruby -Ilib -Itest test/test_builder_baslash.rb
```

Expected: PASS. If no consolidation was needed (only `header_lines` exists),
this step is a no-op.

- [ ] **Step 6: Commit**

```bash
git add lib/baslash/main_ctx.rb lib/baslash/ctx_proxy.rb lib/baslash/builder.rb \
        test/test_main_ctx_baslash.rb test/test_ctx_proxy_baslash.rb test/test_builder_baslash.rb
git commit -m "feat(baslash): port DSL surface (main_ctx / ctx_proxy / builder)"
```

---

## Task 8: Port DefaultCommands, DebugCommands, DebugEndpoint

**Files:**
- Create: `lib/baslash/default_commands.rb` (port)
- Create: `lib/baslash/debug_commands.rb` (port)
- Create: `lib/baslash/debug_endpoint.rb` (port — change ENV from `CCLIKESH_DEBUG` to `BASLASH_DEBUG`)
- Create: `test/test_default_commands_baslash.rb` (port)
- Create: `test/test_debug_commands_baslash.rb` (port)
- Create: `test/test_debug_endpoint_baslash.rb` (port)

- [ ] **Step 1: Move test files with namespace renamed**

```bash
for name in default_commands debug_commands debug_endpoint; do
  cp test/test_${name}.rb test/test_${name}_baslash.rb
  sed -i '' 's/Cclikesh::/Baslash::/g; s/cclikesh\//baslash\//g; s/CCLIKESH_/BASLASH_/g' test/test_${name}_baslash.rb
done
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec ruby -Ilib -Itest test/test_default_commands_baslash.rb
bundle exec ruby -Ilib -Itest test/test_debug_commands_baslash.rb
bundle exec ruby -Ilib -Itest test/test_debug_endpoint_baslash.rb
```

Expected: each fails with `LoadError`.

- [ ] **Step 3: Port implementations**

```bash
for name in default_commands debug_commands debug_endpoint; do
  cp lib/cclikesh/${name}.rb lib/baslash/${name}.rb
  sed -i '' 's/module Cclikesh/module Baslash/g; s/Cclikesh::/Baslash::/g; s/require_relative "cclikesh/require_relative "baslash/g; s/CCLIKESH_/BASLASH_/g' \
    lib/baslash/${name}.rb
done
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/test_default_commands_baslash.rb
bundle exec ruby -Ilib -Itest test/test_debug_commands_baslash.rb
bundle exec ruby -Ilib -Itest test/test_debug_endpoint_baslash.rb
```

Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/baslash/default_commands.rb lib/baslash/debug_commands.rb lib/baslash/debug_endpoint.rb \
        test/test_default_commands_baslash.rb test/test_debug_commands_baslash.rb test/test_debug_endpoint_baslash.rb
git commit -m "feat(baslash): port slash commands (default + debug + endpoint), rename CCLIKESH_ env to BASLASH_"
```

---

## Task 9: Port + simplify RelineDialogs (drop chrome tick, integrate TitleBar)

**Files:**
- Create: `lib/baslash/reline_dialogs.rb` (port + simplify)
- Create: `test/test_reline_dialogs_baslash.rb` (port + adapt)

The new `RelineDialogs` keeps `slash_menu_dialog_proc`, `ghost_text_dialog_proc`, `periodic_tick_proc`, `apply_command`, `drain_main_mailbox`, but replaces the curses `run_chrome_tick` with a minimal `run_tick` that drives `TitleBar.tick`.

- [ ] **Step 1: Write the failing test**

`test/test_reline_dialogs_baslash.rb`:
```ruby
require "test/unit"
require "stringio"
require "baslash/title_bar"
require "baslash/builder"
require "baslash/main_ctx"
require "baslash/reline_dialogs"

class TestRelineDialogsBaslash < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::TitleBar.reset_for_test
    @builder = Baslash::Builder.new
    @builder.info_bar { |_ctx| [{ text: "ctx" }] }
    @main_ctx = Baslash::MainCtx.new(@builder.state_refs)
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_run_tick_drives_title_bar
    Baslash::RelineDialogs.run_tick(@builder, @main_ctx)
    assert_match(/\A\e\]0;✻ /, $stdout.string)
    assert_includes $stdout.string, "ctx"
  end

  def test_run_tick_increments_title_bar_count
    initial = Baslash::TitleBar.tick_count
    Baslash::RelineDialogs.run_tick(@builder, @main_ctx)
    assert_equal initial + 1, Baslash::TitleBar.tick_count
  end

  def test_apply_command_emit_writes_to_stdout
    Baslash::RelineDialogs.apply_command([:emit, "raw bytes"])
    assert_includes $stdout.string, "raw bytes"
  end

  def test_compose_ctx_text_joins_with_dot
    text = Baslash::RelineDialogs.compose_ctx_text(@builder, @main_ctx)
    assert_equal "ctx", text
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec ruby -Ilib -Itest test/test_reline_dialogs_baslash.rb
```

Expected: `LoadError: cannot load such file -- baslash/reline_dialogs`

- [ ] **Step 3: Write the simplified implementation**

`lib/baslash/reline_dialogs.rb`:
```ruby
# frozen_string_literal: true

require "reline"
require "timeout"
require_relative "display"
require_relative "context"
require_relative "title_bar"

module Baslash
  module RelineDialogs
    SLASH_NAME_PAD = 16

    PERIODIC_TICK_TIMEOUT_MS = 120

    SHIFT_ENTER_KEYSTROKES = [
      "\e[27;2;13~".bytes,
      "\e[13;2u".bytes
    ].freeze

    class << self
      attr_accessor :stub_apply_command_for_test

      def install(builder)
        registry = builder.slash_registry
        if Reline.core.config.keyseq_timeout > PERIODIC_TICK_TIMEOUT_MS
          Reline.core.config.keyseq_timeout = PERIODIC_TICK_TIMEOUT_MS
        end
        SHIFT_ENTER_KEYSTROKES.each do |keys|
          Reline.core.config.add_default_key_binding(keys, :key_newline)
        end
        Reline.add_dialog_proc(:periodic_tick, periodic_tick_proc(builder), Reline::DEFAULT_DIALOG_CONTEXT)
        Reline.add_dialog_proc(:autocomplete, slash_menu_dialog_proc(registry), Reline::DEFAULT_DIALOG_CONTEXT)
        Reline.add_dialog_proc(:ghost_text, ghost_text_dialog_proc(registry, nil), Reline::DEFAULT_DIALOG_CONTEXT)
      end

      def periodic_tick_proc(builder)
        main_ctx = Baslash::MainCtx.new(builder.state_refs)
        proc do
          jd = (completion_journey_data rescue nil)
          next nil if jd
          Baslash::RelineDialogs.run_tick(builder, main_ctx)
          nil
        end
      end

      def run_tick(builder, main_ctx)
        drain_main_mailbox
        phase = (Baslash::Context.state[:phase] rescue nil) || :ready
        ctx_text = compose_ctx_text(builder, main_ctx)
        Baslash::TitleBar.tick(phase: phase, ctx_text: ctx_text)
      rescue StandardError => e
        Baslash::Context.logger.error("tick failed: #{e.class}: #{e.message}") rescue nil
        nil
      end

      def compose_ctx_text(builder, main_ctx)
        parts = []
        builder.evaluate_info_bar(main_ctx).each do |item|
          t = (item[:text] || item["text"]).to_s
          parts << t unless t.empty?
        end
        builder.evaluate_status_rows(main_ctx).each do |row|
          segs = row[:segments] || row["segments"] || []
          text = segs.map { |s| (s[:text] || s["text"]).to_s }.reject(&:empty?).join(" ")
          parts << text unless text.empty?
        end
        parts.join(" · ")
      end

      def current_buffer_line(line_editor)
        return "" unless line_editor
        bol = line_editor.instance_variable_get(:@buffer_of_lines)
        idx = line_editor.instance_variable_get(:@line_index) || 0
        return "" unless bol.is_a?(Array)
        bol[idx].to_s
      end

      def slash_menu_dialog_proc(registry)
        proc {
          line = Baslash::RelineDialogs.current_buffer_line(@line_editor)
          cx   = (cursor_pos.x rescue 0)
          next nil unless line.is_a?(String) && line.start_with?("/")
          typed = line[0, cx].to_s
          m = typed.match(/\A\/(\S*)/)
          next nil unless m
          prefix = m[1]
          items =
            begin
              registry.slash_menu_items_starting_with(prefix)
            rescue StandardError => err
              Baslash::Context.logger.error("slash_menu lookup failed: #{err.class}: #{err.message}") rescue nil
              []
            end
          next nil if items.empty?
          contents = Baslash::RelineDialogs.format_slash_lines(items)
          Reline::DialogRenderInfo.new(
            pos:      Reline::CursorPos.new(0, 0),
            contents: contents,
            height:   contents.size,
            width:    Baslash::RelineDialogs.dialog_width(contents),
            face:     :default
          )
        }
      end

      def ghost_text_dialog_proc(registry, ctx)
        proc {
          next nil if completion_journey_data
          line = Baslash::RelineDialogs.current_buffer_line(@line_editor)
          next nil unless line.empty?
          hint = begin
            registry.current_prompt_suggestion(ctx)
          rescue StandardError
            nil
          end
          formatted = Baslash::RelineDialogs.format_ghost_hint(hint)
          next nil unless formatted
          Reline::DialogRenderInfo.new(
            pos:      Reline::CursorPos.new(0, 0),
            contents: [formatted],
            height:   1,
            width:    Baslash::RelineDialogs.visible_width(formatted),
            face:     :default
          )
        }
      end

      def format_slash_line(item)
        name = item[:name].to_s
        desc = item[:description].to_s
        return name if desc.empty?
        pad = [SLASH_NAME_PAD - name.bytesize, 1].max
        "#{name}#{' ' * pad}\e[2;90m#{desc}\e[0m"
      end

      def format_slash_lines(items)
        items.map { |item| format_slash_line(item) }
      end

      def visible_width(line)
        line.gsub(/\e\[[0-9;]*m/, "").bytesize
      end

      def dialog_width(lines)
        return 0 if lines.empty?
        lines.map { |l| visible_width(l) }.max
      end

      def format_ghost_hint(text)
        return nil if text.nil? || text.to_s.empty?
        "\e[2;90m#{text}\e[0m"
      end

      def drain_main_mailbox
        handler = stub_apply_command_for_test || method(:apply_command)
        100.times do
          msg = peek_mailbox
          break unless msg
          handler.call(msg)
        end
      end

      def peek_mailbox
        Ractor.receive_if(timeout: 0) { true }
      rescue NoMethodError, ArgumentError
        begin
          Timeout.timeout(0.001) { Ractor.receive }
        rescue Timeout::Error
          nil
        end
      end

      def apply_command(msg)
        case msg
        in [:append, text, opts]
          Baslash::Display.append(text, **opts)
        in [:open_live_request, reply_to, opts]
          sid = Baslash::Display.open_live(**opts)
          reply_to.send([:open_live_reply, sid])
        in [:live_update, sid, text]
          Baslash::Display.live_update(sid, text)
        in [:live_commit, sid, final]
          Baslash::Display.live_commit(sid, final)
        in [:live_discard, sid]
          Baslash::Display.live_discard(sid)
        in [:dialog, content, opts]
          Baslash::Display.dialog(content, **opts)
        in [:emit, bytes]
          $stdout.write(bytes)
          $stdout.flush
        in [:state_set, key, value]
          Baslash::Context.state_set(key, value)
        in [:state_get_request, reply_to, key]
          reply_to.send([:state_get_reply, Baslash::Context.state[key]])
        in [:debug_snapshot_request, reply_to]
          snapshot = {
            context_state:   Baslash::Context.state.inspect,
            title_bar_phase: Baslash::TitleBar.last_phase.inspect
          }.freeze
          reply_to.send([:debug_snapshot_reply, snapshot])
        in [:debug_tick_count_request, reply_to]
          reply_to.send([:debug_tick_count_reply, Baslash::TitleBar.tick_count])
        in [:debug_curses_caps_request, reply_to]
          reply_to.send([:debug_curses_caps_reply, { term: ENV["TERM"].to_s.freeze }])
        in [:logger, level, text]
          Baslash::Context.logger.send(level, text) rescue nil
        in [:quit]
          Baslash::Context.quit
        else
          # Unknown — ignore
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bundle exec ruby -Ilib -Itest test/test_reline_dialogs_baslash.rb
```

Expected: `4 tests, ≥4 assertions, 0 failures, 0 errors`

- [ ] **Step 5: Commit**

```bash
git add lib/baslash/reline_dialogs.rb test/test_reline_dialogs_baslash.rb
git commit -m "feat(baslash): RelineDialogs ported + simplified — drop curses chrome tick, integrate TitleBar"
```

---

## Task 10: Build new Runner (slim, no curses)

**Files:**
- Create: `lib/baslash/runner.rb` (rewrite)
- Modify: `lib/baslash.rb` (wire up `Baslash.run`)
- Create: `test/test_runner_baslash.rb`

The new `Runner` is just: signal trap, Reline orchestration, main read loop, slash dispatch, quit handling. No curses init/teardown, no terminfo overlay, no DECSC/DECRC.

- [ ] **Step 1: Write the failing test**

`test/test_runner_baslash.rb`:
```ruby
require "test/unit"
require "baslash/runner"
require "baslash/builder"

class TestRunnerBaslash < Test::Unit::TestCase
  def test_prompt_text_returns_default
    builder = Baslash::Builder.new
    assert_equal "> ", Baslash::Runner.prompt_text(builder)
  end

  def test_install_completion_no_op_without_handler
    builder = Baslash::Builder.new
    assert_nothing_raised { Baslash::Runner.install_completion(builder) }
  end

  def test_run_module_methods_exist
    %i[run prompt_text install_completion].each do |sym|
      assert_respond_to Baslash::Runner, sym, "Runner should respond to #{sym}"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec ruby -Ilib -Itest test/test_runner_baslash.rb
```

Expected: `LoadError: cannot load such file -- baslash/runner`

- [ ] **Step 3: Write the implementation**

`lib/baslash/runner.rb`:
```ruby
# frozen_string_literal: true

require "reline"
require_relative "default_commands"
require_relative "debug_commands"
require_relative "display"
require_relative "title_bar"
require_relative "reline_dialogs"
require_relative "context"
require_relative "main_ctx"
require_relative "slash_dispatcher"

Warning[:experimental] = false

module Baslash
  module Runner
    def self.run(builder)
      Context.init(logger: builder.logger)
      if defined?(Baslash::DebugEndpoint)
        Baslash::DebugEndpoint.start_if_enabled(builder)
      end

      install_completion(builder)
      RelineDialogs.install(builder)
      DefaultCommands.register(builder.slash_registry)
      if builder.debug_commands_enabled? || ENV["BASLASH_DEBUG"]
        Baslash::DebugCommands.register(builder.slash_registry, tick_counter: Baslash::TitleBar)
      end
      DefaultCommands.register_help(builder.slash_registry)

      main_ctx = MainCtx.new(builder.state_refs)
      builder.header_lines.each { |line| Display.append(line) }
      hint = builder.shortcuts_hint_text.to_s
      Display.append(hint) unless hint.empty?
      TitleBar.tick(phase: :ready, ctx_text: RelineDialogs.compose_ctx_text(builder, main_ctx))

      builder.on_start_handlers.each { |h| h.call(nil) rescue nil }

      catch(:quit) do
        loop do
          line = nil
          begin
            line = Reline.readmultiline(prompt_text(builder), true) { true }
          rescue Interrupt
            RelineDialogs.drain_main_mailbox
            throw :quit if Context.quit?
            next
          end
          throw :quit if line.nil?
          throw :quit if Context.quit?
          line = line.to_s
          next if line.strip.empty?
          begin
            SlashDispatcher.handle(
              line,
              builder.slash_registry,
              Ractor.current,
              on_submit: builder.on_submit_handler,
              state_refs: builder.state_refs
            )
          rescue Interrupt
            RelineDialogs.drain_main_mailbox
            throw :quit if Context.quit?
          end
        end
      end

      builder.on_quit_handlers.each { |h| h.call(nil) rescue nil }
    ensure
      TitleBar.restore
      builder.state_refs.each_value { |ref| ref.stop rescue nil }
    end

    def self.prompt_text(_builder)
      "> "
    end

    def self.install_completion(builder)
      return unless builder.on_tab_handler
      Reline.completion_proc = builder.on_tab_handler
    end
  end
end
```

Modify `lib/baslash.rb` to wire everything:
```ruby
# frozen_string_literal: true

require_relative "baslash/version"
require_relative "baslash/style"
require_relative "baslash/title_bar"
require_relative "baslash/transcript"
require_relative "baslash/context"
require_relative "baslash/main_ctx"
require_relative "baslash/display"
require_relative "baslash/shareable_ref"
require_relative "baslash/slash_registry"
require_relative "baslash/ctx_proxy"
require_relative "baslash/handler_ractor"
require_relative "baslash/slash_dispatcher"
require_relative "baslash/default_commands"
require_relative "baslash/debug_commands"
require_relative "baslash/reline_dialogs"
require_relative "baslash/builder"
begin
  require_relative "baslash/debug_endpoint"
rescue LoadError
  # opt-in
end
require_relative "baslash/runner"

module Baslash
  def self.run(&block)
    builder = Builder.new
    block.call(builder)
    Runner.run(builder)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/test_runner_baslash.rb
bundle exec ruby -Ilib -Itest test/test_baslash_gem.rb  # also re-verify gem skeleton
```

Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/baslash/runner.rb lib/baslash.rb test/test_runner_baslash.rb
git commit -m "feat(baslash): slim Runner (no curses) + wire Baslash.run entry point"
```

---

## Task 11: Migrate examples to Baslash.run

**Files:**
- Modify: `examples/echo_shell.rb`
- Modify: `examples/zsh_shell/zsh_shell.rb`
- Modify: `examples/zsh_shell/*.rb` (if any reference `Cclikesh::*`)
- Modify: `examples/irb_shell/irb_shell.rb`
- Modify: `examples/irb_shell/*.rb` (if any reference `Cclikesh::*`)

- [ ] **Step 1: Audit current example references**

```bash
grep -rn "Cclikesh\|cclikesh" examples/
```

Note every match.

- [ ] **Step 2: Write a smoke test for echo_shell boot+exit**

`test/test_examples_smoke_baslash.rb`:
```ruby
require "test/unit"
require "open3"

class TestExamplesSmokeBaslash < Test::Unit::TestCase
  REPO_ROOT = File.expand_path("..", __dir__)

  def test_echo_shell_boots_and_quits
    cmd = "bundle exec ruby examples/echo_shell.rb"
    Open3.popen2e(cmd, chdir: REPO_ROOT) do |stdin, out, wait_thr|
      stdin.puts "/exit"
      stdin.close
      Timeout.timeout(15) { wait_thr.value }
      output = out.read
      assert_equal 0, wait_thr.value.exitstatus, "echo_shell should exit cleanly. Output: #{output[-2000..]}"
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

```bash
bundle exec ruby -Ilib -Itest test/test_examples_smoke_baslash.rb
```

Expected: FAIL — examples still reference `Cclikesh.run` which now doesn't exist.

- [ ] **Step 4: Migrate examples**

```bash
find examples -type f -name '*.rb' -exec sed -i '' 's/Cclikesh\.run/Baslash.run/g; s/Cclikesh::/Baslash::/g; s/require "cclikesh/require "baslash/g; s/CCLIKESH_/BASLASH_/g' {} \;
```

- [ ] **Step 5: Run test to verify it passes**

```bash
bundle exec ruby -Ilib -Itest test/test_examples_smoke_baslash.rb
```

Expected: PASS within 15s.

- [ ] **Step 6: Commit**

```bash
git add examples/ test/test_examples_smoke_baslash.rb
git commit -m "feat(examples): migrate echo/zsh/irb shells to Baslash.run"
```

---

## Task 12: Migrate cclikesh-debug → baslash-debug

**Files:**
- Rename: `cclikesh-debug/` → `baslash-debug/`
- Rename: `cclikesh-debug/exe/cclikesh-debug` → `baslash-debug/exe/baslash-debug`
- Rename: `cclikesh-debug/cclikesh-debug.gemspec` → `baslash-debug/baslash-debug.gemspec`
- Rename: `cclikesh-debug/lib/cclikesh/debug/` → `baslash-debug/lib/baslash/debug/`
- Rename: `cclikesh-debug/test/cclikesh-debug/` → `baslash-debug/test/baslash-debug/`
- Modify: every file inside the renamed tree (sed namespace)

- [ ] **Step 1: Audit current debug-gem cross-references**

```bash
grep -rln "Cclikesh::Debug\|cclikesh-debug\|cclikesh/debug" cclikesh-debug/ | head -50
```

- [ ] **Step 2: Rename directories and gemspec**

```bash
git mv cclikesh-debug baslash-debug
git mv baslash-debug/exe/cclikesh-debug          baslash-debug/exe/baslash-debug
git mv baslash-debug/cclikesh-debug.gemspec      baslash-debug/baslash-debug.gemspec
git mv baslash-debug/lib/cclikesh                baslash-debug/lib/baslash
git mv baslash-debug/test/cclikesh-debug         baslash-debug/test/baslash-debug
```

- [ ] **Step 3: Sed namespace inside the renamed tree**

```bash
find baslash-debug -type f \( -name '*.rb' -o -name '*.gemspec' \) -exec \
  sed -i '' \
    -e 's/Cclikesh::Debug/Baslash::Debug/g' \
    -e 's/cclikesh-debug/baslash-debug/g' \
    -e 's/cclikesh\/debug/baslash\/debug/g' \
    -e 's/CCLIKESH_/BASLASH_/g' \
    -e 's/spec\.name *= *"cclikesh-debug"/spec.name = "baslash-debug"/g' \
    {} \;
```

Adjust the `exe/baslash-debug` shebang/require lines explicitly:
```bash
sed -i '' 's/cclikesh-debug/baslash-debug/g; s/cclikesh\/debug/baslash\/debug/g' baslash-debug/exe/baslash-debug
chmod +x baslash-debug/exe/baslash-debug
```

- [ ] **Step 4: Update `cclikesh-debug` references in PTY specs**

The PTY specs spawn `bundle exec ruby examples/zsh_shell/zsh_shell.rb`. After Task 11 those examples no longer use `cclikesh`. No further change needed in spec invocation strings.

Verify with:
```bash
grep -rn "cclikesh\|Cclikesh" baslash-debug/
```

Expected: no remaining matches.

- [ ] **Step 5: Run the full debug-gem test suite**

```bash
cd baslash-debug && bundle exec rake test 2>&1 | tail -10
cd ..
```

Expected: all tests PASS at the same count as before the rename (current: 80 tests).

- [ ] **Step 6: Run all PTY specs from repo root to confirm cwd workflow**

```bash
bundle exec ruby baslash-debug/exe/baslash-debug pty-list 2>&1 | head -5
bundle exec ruby baslash-debug/exe/baslash-debug play baslash-debug/test/specs/cmux_env_resize_cursor.rb 2>&1 | tail -5
bundle exec ruby baslash-debug/exe/baslash-debug play baslash-debug/test/specs/cmux_env_slash_layout.rb 2>&1 | tail -5
bundle exec ruby baslash-debug/exe/baslash-debug play baslash-debug/test/specs/cmux_env_resize_divider.rb 2>&1 | tail -5
```

Expected: each prints `PASS:` lines and `recorded (N events, T s)` with N>=20 (R-spec PASS count from the previous handoff).

- [ ] **Step 7: Commit**

```bash
git add -A baslash-debug
git rm -rf cclikesh-debug 2>/dev/null || true
git commit -m "feat(debug): rename cclikesh-debug -> baslash-debug + namespace + paths"
```

---

## Task 13: Cleanup — delete lib/cclikesh + cclikesh.gemspec + obsolete tests

**Files:**
- Delete: `lib/cclikesh.rb`
- Delete: `lib/cclikesh/` (entire tree)
- Delete: `cclikesh.gemspec`
- Delete: `test/test_chrome.rb`
- Delete: `test/test_chrome_layout_diag.rb`
- Delete: `test/test_terminfo_overlay.rb`
- Delete: `test/test_layout_diag.rb`
- Delete: `test/test_display_layout_diag.rb`
- Delete: `test/test_runner_layout_diag.rb`
- Delete: `test/test_curses_integration.rb`
- Modify: `README.md` (rename + scope statement)
- Modify: `CHANGELOG.md` if exists (add v0.3.0 entry)

- [ ] **Step 1: Verify nothing still imports cclikesh**

```bash
grep -rln "Cclikesh\|require.*cclikesh\|cclikesh\.gemspec" \
  --exclude-dir=docs --exclude-dir=.git \
  --exclude='*.md' --exclude='Gemfile.lock' \
  . | head -20
```

Expected: no matches outside `docs/superpowers/` and `lib/cclikesh/`.

- [ ] **Step 2: Delete the obsolete tests first (so the test suite stops needing curses)**

```bash
git rm test/test_chrome.rb test/test_chrome_layout_diag.rb \
       test/test_terminfo_overlay.rb test/test_layout_diag.rb \
       test/test_display_layout_diag.rb test/test_runner_layout_diag.rb \
       test/test_curses_integration.rb
```

- [ ] **Step 3: Run full test suite — should still pass with only the new tests**

```bash
bundle exec rake test 2>&1 | tail -8
```

Expected: PASS at the new lower count (current 181 minus the deleted tests' counts, plus the new baslash tests).

- [ ] **Step 4: Delete the old library tree and gemspec**

```bash
git rm cclikesh.gemspec lib/cclikesh.rb
git rm -rf lib/cclikesh
```

- [ ] **Step 5: Update README**

`README.md` (replace top of file):
```markdown
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
```

- [ ] **Step 6: Run full test suite again to confirm everything still passes**

```bash
bundle exec rake test 2>&1 | tail -8
cd baslash-debug && bundle exec rake test 2>&1 | tail -8 ; cd ..
```

Expected: both green.

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "chore(baslash): delete cclikesh library tree + obsolete curses tests; update README"
```

---

## Task 14: Real-TTY smoke + handoff

**Files:**
- Create: `docs/superpowers/handoff/2026-05-15-baslash-v1-shipped.md`

This task is human-in-the-loop. The implementer runs the example shells in real terminals and records observations.

- [ ] **Step 1: Run echo_shell on Terminal.app**

In Terminal.app (not via PTY harness), run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell
bundle exec ruby examples/echo_shell.rb
```

Verify in this order:
1. Banner appears in scrollable area, cursor lands at the prompt below.
2. Title bar shows `✻ <ctx text>` (whatever info_bar / status_rows produce).
3. Type `/` — slash menu autocomplete appears.
4. Type `/help<Enter>` — help text appears in the body, prompt redraws below.
5. Echo a long line — verify it appears in body and scrolls naturally.
6. Generate ~100 lines (e.g., paste a long block, or use `/transcript` after several inputs) — verify mouse-wheel scrollback reaches the boot banner.
7. Resize the window (drag edge) — verify next prompt re-renders correctly.
8. Type `/exit<Enter>` — verify shell exits with title restored.

Record observations in the handoff doc (Step 4).

- [ ] **Step 2: Run zsh_shell on Terminal.app**

```bash
bundle exec ruby examples/zsh_shell/zsh_shell.rb
```

Repeat the same 8-point verification.

- [ ] **Step 3: Run echo_shell inside cmux**

Inside an active cmux session:
```bash
bundle exec ruby examples/echo_shell.rb
```

Repeat the verification. Note any cmux-specific behavior (e.g., title bar passthrough).

- [ ] **Step 4: Write the handoff doc**

`docs/superpowers/handoff/2026-05-15-baslash-v1-shipped.md`:

Use this template (fill in actual observations):
```markdown
# baslash v1 ship — real-TTY smoke results

**Date:** 2026-05-15
**Spec:** docs/superpowers/specs/2026-05-15-baslash-rename-and-zsh-style-pivot-design.md
**Plan:** docs/superpowers/plans/2026-05-15-baslash-rename-and-zsh-style-pivot.md

## Test matrix

| Shell | Terminal | Banner OK | Title OK | Slash menu | /help | Long output | Scrollback to banner | Resize | Clean exit |
|---|---|---|---|---|---|---|---|---|---|
| echo_shell | Terminal.app | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| zsh_shell  | Terminal.app | ... | ... | ... | ... | ... | ... | ... | ... |
| echo_shell | cmux         | ... | ... | ... | ... | ... | ... | ... | ... |

## Notes

(record any oddities, cmux passthrough behavior, terminal-specific quirks, etc.)

## Test suite at ship time

- root: N tests, 0 failures, 0 errors, M omissions
- baslash-debug: N tests, 0 failures, 0 errors, M omissions

## Open follow-ups (if any)

(list anything that could not be addressed and why)
```

- [ ] **Step 5: Commit the handoff doc**

```bash
git add -f docs/superpowers/handoff/2026-05-15-baslash-v1-shipped.md
git commit -m "docs(handoff): baslash v1 real-TTY smoke results on Terminal.app + cmux"
```

---

## Acceptance verification (final pass)

Run all of the following and confirm green:

```bash
bundle exec rake test 2>&1 | tail -8
cd baslash-debug && bundle exec rake test 2>&1 | tail -8 ; cd ..
grep -rln "Cclikesh\|cclikesh" --exclude-dir=docs --exclude-dir=.git --exclude='*.md' --exclude='Gemfile.lock' .
```

Expected:
- root suite: green
- baslash-debug suite: green
- grep: no matches outside `docs/superpowers/` (the spec / plan / handoff history retains the old name for traceability)

If all three are clean, the implementation is complete.
