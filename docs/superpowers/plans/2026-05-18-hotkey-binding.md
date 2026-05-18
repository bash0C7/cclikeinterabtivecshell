# Hotkey Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `shell.slash(...)` accept a `hotkey:` keyword (default `nil`) that binds a single key (or chord) so that pressing it from an empty prompt dispatches the command through the existing slash path. Default-off; reserved keys raise; surfaced in `/help` and the slash-menu dialog.

**Architecture:** Approach A — `Baslash::HotkeyInstaller` defines a per-command instance method on `Reline::LineEditor` (`__baslash_hotkey_<name>`) and binds the parsed byte sequence with `Reline.core.config.add_default_key_binding`. The method gates on `current_line.empty? && @buffer_of_lines.size == 1`, then `set_current_line("/<name>", bytesize)` + `finish`, so dispatch flows through the normal Reline submit path and existing `SlashDispatcher.handle`. Reline 0.6.3's `wrap_method_call` (line 949 of `reline/line_editor.rb`) verified to dispatch via `__send__(symbol)` and to reject non-method targets, so lambda binding is not viable.

**Tech Stack:** Ruby (CRuby 4.0.x), Reline 0.6.3, test-unit, Bundler. No new gem dependencies.

**Spec reference:** `docs/superpowers/specs/2026-05-18-hotkey-binding-design.md`

---

## File Structure

New files:

- `lib/baslash/hotkey_spec.rb` — pure-Ruby key string parser/formatter, reserved-key list, `Baslash::HotkeyError`.
- `lib/baslash/hotkey_installer.rb` — registry iteration + `Reline::LineEditor.define_method` + `add_default_key_binding`.
- `test/test_hotkey_spec_baslash.rb` — unit tests for `HotkeySpec.parse / format / reserved? / errors`.
- `test/test_hotkey_installer_baslash.rb` — unit tests for installer (registry skip when nil, conflict warn, gate behavior tested indirectly via a stub LineEditor).

Modified files:

- `lib/baslash/slash_registry.rb` — `register` takes `hotkey:`; entry stores it; `slash_menu_items_starting_with` returns it.
- `lib/baslash/builder.rb` — `slash` accepts `hotkey:`; block-less form updates an existing entry.
- `lib/baslash/runner.rb` — call `HotkeyInstaller.install(builder)` after `DefaultCommands.register_help`.
- `lib/baslash/reline_dialogs.rb` — `format_slash_line` appends ` (C-g)` dim suffix when present.
- `lib/baslash/default_commands.rb` — `register_help` snapshot includes hotkey; rendered with dim suffix.
- `lib/baslash.rb` — `require_relative` the two new files.
- `test/test_slash_registry_baslash.rb` — extend.
- `test/test_builder_baslash.rb` — extend.
- `test/test_default_commands_baslash.rb` — extend.
- `test/test_reline_dialogs_baslash.rb` — extend.
- `README.md` — document `hotkey:` kwarg, reserved keys, default-off.
- `examples/zsh_shell/zsh_shell.rb` — one demonstrative `hotkey: "C-g"` on `/reset`.
- `examples/ptyblues_recording/04_tty_e2e.rb` — add a scenario that binds `C-g` to a custom command and asserts dispatch behavior (and buffer-non-empty gate).

---

## Task 1: HotkeySpec parser — letter forms

**Files:**
- Create: `lib/baslash/hotkey_spec.rb`
- Create: `test/test_hotkey_spec_baslash.rb`

- [x] **Step 1: Write the failing tests**

```ruby
# test/test_hotkey_spec_baslash.rb
# frozen_string_literal: true

require_relative "test_helper"
require "baslash/hotkey_spec"

class TestHotkeySpecBaslash < Test::Unit::TestCase
  def test_parse_ctrl_letter
    assert_equal [7],  Baslash::HotkeySpec.parse("C-g")
    assert_equal [1],  Baslash::HotkeySpec.parse("C-a")
    assert_equal [26], Baslash::HotkeySpec.parse("C-z")
  end

  def test_parse_ctrl_letter_case_insensitive
    assert_equal [7], Baslash::HotkeySpec.parse("c-g")
    assert_equal [7], Baslash::HotkeySpec.parse("C-G")
  end

  def test_parse_meta_letter
    assert_equal [27, 100], Baslash::HotkeySpec.parse("M-d")
    assert_equal [27, 97],  Baslash::HotkeySpec.parse("M-a")
  end

  def test_parse_meta_digit
    assert_equal [27, 49], Baslash::HotkeySpec.parse("M-1")
    assert_equal [27, 48], Baslash::HotkeySpec.parse("M-0")
  end
end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TESTOPTS="-n /HotkeySpec/"`
Expected: `LoadError: cannot load such file -- baslash/hotkey_spec`

- [x] **Step 3: Write minimal implementation**

```ruby
# lib/baslash/hotkey_spec.rb
# frozen_string_literal: true

module Baslash
  class HotkeyError < StandardError; end

  module HotkeySpec
    CTRL_LETTER = /\AC-([a-zA-Z])\z/.freeze
    META_LETTER = /\AM-([a-zA-Z0-9])\z/.freeze

    def self.parse(spec)
      raise HotkeyError, "hotkey spec must be a non-empty String" unless spec.is_a?(String) && !spec.empty?
      tokens = spec.split(/\s+/)
      raise HotkeyError, "hotkey spec is empty after splitting" if tokens.empty?
      bytes = tokens.flat_map { |t| parse_token(t) }
      bytes
    end

    def self.parse_token(tok)
      if (m = CTRL_LETTER.match(tok))
        ch = m[1].downcase.ord
        [ch - 96]
      elsif (m = META_LETTER.match(tok))
        [27, m[1].ord]
      else
        raise HotkeyError, "invalid hotkey token: #{tok.inspect}"
      end
    end
  end
end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TESTOPTS="-n /HotkeySpec/"`
Expected: 4 passed, 0 failed.

- [x] **Step 5: Commit**

```bash
git add lib/baslash/hotkey_spec.rb test/test_hotkey_spec_baslash.rb
git commit -m "feat(hotkey): add HotkeySpec parser for C-/M- letter and M-digit forms"
```

---

## Task 2: HotkeySpec chord + error cases + reserved + format

**Files:**
- Modify: `lib/baslash/hotkey_spec.rb`
- Modify: `test/test_hotkey_spec_baslash.rb`

- [x] **Step 1: Write the failing tests**

Append to `test/test_hotkey_spec_baslash.rb`:

```ruby
  def test_parse_chord
    assert_equal [24, 18], Baslash::HotkeySpec.parse("C-x C-r")
  end

  def test_parse_chord_extra_whitespace
    assert_equal [24, 18], Baslash::HotkeySpec.parse("C-x   C-r")
  end

  def test_parse_empty_raises
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("") }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("   ") }
  end

  def test_parse_unknown_token_raises
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("foo") }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("C-") }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("X-y") }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("M-foo") }
  end

  def test_parse_non_string_raises
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse(nil) }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse(42) }
  end

  def test_reserved_keys_raise
    %w[C-c C-m C-j C-i C-h].each do |k|
      assert_raise(Baslash::HotkeyError, "expected reserved: #{k}") do
        Baslash::HotkeySpec.parse(k)
      end
    end
  end

  def test_format_round_trip
    assert_equal "C-g",     Baslash::HotkeySpec.format("C-g")
    assert_equal "C-G",     Baslash::HotkeySpec.format("c-g").upcase[0,1] + Baslash::HotkeySpec.format("c-g")[1..]
    # canonical form: capital C, lowercase letter
    assert_equal "C-g",     Baslash::HotkeySpec.format("c-G")
    assert_equal "M-d",     Baslash::HotkeySpec.format("M-D")
    assert_equal "C-x C-r", Baslash::HotkeySpec.format("c-X c-r")
  end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TESTOPTS="-n /HotkeySpec/"`
Expected: empty/reserved/format tests fail (existing 4 still pass).

- [x] **Step 3: Update implementation**

Replace `lib/baslash/hotkey_spec.rb` with:

```ruby
# frozen_string_literal: true

module Baslash
  class HotkeyError < StandardError; end

  module HotkeySpec
    CTRL_LETTER = /\AC-([a-zA-Z])\z/.freeze
    META_LETTER = /\AM-([a-zA-Z0-9])\z/.freeze

    # Byte sequences we refuse to bind because they are load-bearing in the
    # baslash UX: Ctrl-C interrupts a handler, Enter/LF submit, Tab opens the
    # slash menu / completion, Backspace deletes a char. Binding any of these
    # would silently take over a critical input.
    RESERVED_BYTES = [
      [3],  # C-c SIGINT
      [13], # C-m CR / Enter
      [10], # C-j LF
      [9],  # C-i TAB
      [8]   # C-h backspace
    ].freeze

    def self.parse(spec)
      unless spec.is_a?(String) && !spec.strip.empty?
        raise HotkeyError, "hotkey spec must be a non-empty String, got #{spec.inspect}"
      end
      tokens = spec.split(/\s+/).reject(&:empty?)
      raise HotkeyError, "hotkey spec is empty after splitting: #{spec.inspect}" if tokens.empty?
      bytes = tokens.flat_map { |t| parse_token(t) }
      if RESERVED_BYTES.include?(bytes)
        raise HotkeyError, "hotkey #{spec.inspect} is reserved by baslash"
      end
      bytes
    end

    # Canonical form: "C-g", "M-d", "C-x C-r" — uppercase modifier, lowercase letter.
    def self.format(spec)
      tokens = spec.to_s.split(/\s+/).reject(&:empty?)
      tokens.map { |t| format_token(t) }.join(" ")
    end

    def self.parse_token(tok)
      if (m = CTRL_LETTER.match(tok))
        [m[1].downcase.ord - 96]
      elsif (m = META_LETTER.match(tok))
        ch = m[1]
        b = ch.match?(/[A-Z]/) ? ch.downcase.ord : ch.ord
        [27, b]
      else
        raise HotkeyError, "invalid hotkey token: #{tok.inspect}"
      end
    end

    def self.format_token(tok)
      if (m = CTRL_LETTER.match(tok))
        "C-#{m[1].downcase}"
      elsif (m = META_LETTER.match(tok))
        ch = m[1]
        ch = ch.downcase if ch.match?(/[A-Z]/)
        "M-#{ch}"
      else
        raise HotkeyError, "invalid hotkey token: #{tok.inspect}"
      end
    end
  end
end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TESTOPTS="-n /HotkeySpec/"`
Expected: all HotkeySpec tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/baslash/hotkey_spec.rb test/test_hotkey_spec_baslash.rb
git commit -m "feat(hotkey): support chord, error cases, reserved keys, format round-trip"
```

---

## Task 3: SlashRegistry — accept and expose hotkey

**Files:**
- Modify: `lib/baslash/slash_registry.rb`
- Modify: `test/test_slash_registry_baslash.rb`

- [x] **Step 1: Write the failing tests**

Append to `test/test_slash_registry_baslash.rb`:

```ruby
  def test_register_stores_hotkey
    reg = Baslash::SlashRegistry.new
    reg.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    entry = reg.lookup(:reset)
    assert_equal "C-g", entry[:hotkey]
  end

  def test_register_defaults_hotkey_to_nil
    reg = Baslash::SlashRegistry.new
    reg.register(:reset, proc {}, description: "reset")
    assert_nil reg.lookup(:reset)[:hotkey]
  end

  def test_slash_menu_items_include_hotkey
    reg = Baslash::SlashRegistry.new
    reg.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    reg.register(:plain, proc {}, description: "plain")
    items = reg.slash_menu_items_starting_with("")
    reset = items.find { |i| i[:name] == "/reset" }
    plain = items.find { |i| i[:name] == "/plain" }
    assert_equal "C-g", reset[:hotkey]
    assert_nil   plain[:hotkey]
  end

  def test_update_hotkey_for_existing_entry
    reg = Baslash::SlashRegistry.new
    body = proc {}
    reg.register(:exit, body, description: "exit")
    reg.update_hotkey(:exit, "C-d")
    entry = reg.lookup(:exit)
    assert_equal "C-d", entry[:hotkey]
    assert_same body, entry[:body]
    assert_equal "exit", entry[:description]
  end

  def test_update_hotkey_on_unknown_name_raises
    reg = Baslash::SlashRegistry.new
    assert_raise(KeyError) { reg.update_hotkey(:nope, "C-g") }
  end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TESTOPTS="-n /SlashRegistry/"`
Expected: 5 new tests fail (existing pass).

- [x] **Step 3: Update implementation**

Replace `lib/baslash/slash_registry.rb` with:

```ruby
# frozen_string_literal: true

module Baslash
  class SlashRegistry
    def initialize
      @entries = {}
    end

    def register(name, body, description: nil, hotkey: nil)
      @entries[name.to_sym] = {
        body:        body,
        description: description.to_s.freeze,
        hotkey:      hotkey ? hotkey.to_s.freeze : nil
      }.freeze
    end

    # Update only the hotkey of an existing entry, preserving body and
    # description. Used by the block-less Builder#slash form so users can
    # attach a hotkey to a framework built-in (/exit, /help, ...) without
    # redefining its body. Raises KeyError if the entry does not exist.
    def update_hotkey(name, hotkey)
      sym = name.to_sym
      entry = @entries[sym] or raise KeyError, "no slash command registered: /#{sym}"
      @entries[sym] = {
        body:        entry[:body],
        description: entry[:description],
        hotkey:      hotkey ? hotkey.to_s.freeze : nil
      }.freeze
    end

    def lookup(name)
      return nil if name.nil? || name.to_s.empty?
      @entries[name.to_sym]
    end

    def each(&block)
      @entries.each(&block)
    end

    def all
      @entries.dup.freeze
    end

    # Items consumed by the slash-menu dialog. Returns every entry whose
    # name (without the leading slash) starts with `prefix`. The dialog
    # uses :name (with the slash), :description, and :hotkey verbatim, so
    # we synthesize the displayed name here. Result order matches insertion
    # order so default + plugin + user-extension layering is preserved.
    def slash_menu_items_starting_with(prefix)
      prefix_str = prefix.to_s
      result = []
      @entries.each do |name, entry|
        name_str = name.to_s
        next unless name_str.start_with?(prefix_str)
        result << {
          name:        "/#{name_str}",
          description: entry[:description],
          hotkey:      entry[:hotkey]
        }
      end
      result
    end
  end
end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TESTOPTS="-n /SlashRegistry/"`
Expected: all SlashRegistry tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/baslash/slash_registry.rb test/test_slash_registry_baslash.rb
git commit -m "feat(hotkey): SlashRegistry stores hotkey + update_hotkey"
```

---

## Task 4: Builder — `hotkey:` kwarg + block-less update form

**Files:**
- Modify: `lib/baslash/builder.rb`
- Modify: `test/test_builder_baslash.rb`

- [x] **Step 1: Write the failing tests**

Append to `test/test_builder_baslash.rb` (above the prompt_prefix section):

```ruby
  # --- slash hotkey ---

  def test_slash_with_hotkey_stores_hotkey
    b = Baslash::Builder.new
    b.slash(:reset, description: "reset", hotkey: "C-g") { |_, _| }
    assert_equal "C-g", b.slash_registry.lookup(:reset)[:hotkey]
  end

  def test_slash_validates_hotkey_at_registration
    b = Baslash::Builder.new
    assert_raise(Baslash::HotkeyError) do
      b.slash(:reset, description: "reset", hotkey: "bogus") { |_, _| }
    end
  end

  def test_slash_rejects_reserved_hotkey
    b = Baslash::Builder.new
    assert_raise(Baslash::HotkeyError) do
      b.slash(:reset, description: "reset", hotkey: "C-c") { |_, _| }
    end
  end

  def test_slash_blockless_updates_hotkey_on_existing_entry
    b = Baslash::Builder.new
    b.slash(:reset, description: "reset") { |_, _| }
    b.slash(:reset, hotkey: "C-g")
    assert_equal "C-g", b.slash_registry.lookup(:reset)[:hotkey]
  end

  def test_slash_blockless_on_unknown_name_raises
    b = Baslash::Builder.new
    assert_raise(Baslash::HotkeyError) do
      b.slash(:nope, hotkey: "C-g")
    end
  end

  def test_slash_blockless_without_hotkey_is_noop_error
    b = Baslash::Builder.new
    b.slash(:reset, description: "reset") { |_, _| }
    # No block and no hotkey: nothing meaningful to update.
    assert_raise(Baslash::HotkeyError) { b.slash(:reset) }
  end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TESTOPTS="-n /test_slash_with_hotkey|test_slash_validates|test_slash_rejects_reserved|test_slash_blockless/"`
Expected: 6 fails.

- [x] **Step 3: Update implementation**

Add `require_relative "hotkey_spec"` near the top of `lib/baslash/builder.rb`:

```ruby
require "logger"
require_relative "slash_registry"
require_relative "style"
require_relative "hotkey_spec"
```

Replace the `def slash` method (currently around line 173):

```ruby
    def slash(name, description: nil, hotkey: nil, &block)
      if block.nil?
        unless hotkey
          raise HotkeyError, "Builder#slash without a block requires `hotkey:` (no-op call for /#{name})"
        end
        # Validate spec before mutating the registry — fail fast.
        Baslash::HotkeySpec.parse(hotkey)
        begin
          @slash_registry.update_hotkey(name.to_sym, hotkey)
        rescue KeyError
          raise HotkeyError, "cannot attach hotkey to unknown command /#{name}"
        end
        return self
      end
      Baslash::HotkeySpec.parse(hotkey) if hotkey
      @slash_registry.register(name.to_sym, block, description: description, hotkey: hotkey)
    end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TESTOPTS="-n /Builder/"`
Expected: all Builder tests pass (existing + new).

- [x] **Step 5: Commit**

```bash
git add lib/baslash/builder.rb test/test_builder_baslash.rb
git commit -m "feat(hotkey): Builder#slash accepts hotkey: kwarg and block-less update"
```

---

## Task 5: HotkeyInstaller — define methods + bind keys

**Files:**
- Create: `lib/baslash/hotkey_installer.rb`
- Create: `test/test_hotkey_installer_baslash.rb`

- [x] **Step 1: Write the failing tests**

```ruby
# test/test_hotkey_installer_baslash.rb
# frozen_string_literal: true

require_relative "test_helper"
require "logger"
require "stringio"
require "reline"
require "baslash/slash_registry"
require "baslash/hotkey_installer"

class TestHotkeyInstallerBaslash < Test::Unit::TestCase
  def setup
    @log_io = StringIO.new
    @logger = Logger.new(@log_io)
    @registry = Baslash::SlashRegistry.new
    @builder = StubBuilder.new(@registry, @logger)
    Reline.core.config.reset
  end

  def test_install_skips_entries_without_hotkey
    @registry.register(:plain, proc {}, description: "plain")
    Baslash::HotkeyInstaller.install(@builder)
    # No method created, no binding emitted -> nothing in log
    assert_empty @log_io.string
  end

  def test_install_defines_method_on_line_editor
    @registry.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    assert Reline::LineEditor.method_defined?(:__baslash_hotkey_reset) ||
           Reline::LineEditor.private_method_defined?(:__baslash_hotkey_reset),
           "expected __baslash_hotkey_reset to be defined on Reline::LineEditor"
  end

  def test_install_warns_on_duplicate_byte_sequence
    @registry.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    @registry.register(:other, proc {}, description: "other", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    assert_includes @log_io.string, "hotkey conflict"
    assert_includes @log_io.string, "C-g"
  end

  def test_install_is_idempotent_across_method_redefinition
    @registry.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    # Calling install a second time with the same registry must not raise.
    assert_nothing_raised { Baslash::HotkeyInstaller.install(@builder) }
  end

  def test_hotkey_method_inserts_command_and_finishes
    @registry.register(:marker, proc {}, description: "marker", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    fake = FakeLineEditor.new(buffer: [""], line_index: 0)
    fake.send(:__baslash_hotkey_marker, [7])
    assert_equal ["/marker"], fake.buffer
    assert_equal "/marker".bytesize, fake.byte_pointer
    assert fake.finished?
  end

  def test_hotkey_method_noop_when_buffer_nonempty
    @registry.register(:marker, proc {}, description: "marker", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    fake = FakeLineEditor.new(buffer: ["already typing"], line_index: 0)
    fake.send(:__baslash_hotkey_marker, [7])
    assert_equal ["already typing"], fake.buffer
    refute fake.finished?
  end

  def test_hotkey_method_noop_when_multiline_edit
    @registry.register(:marker, proc {}, description: "marker", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    fake = FakeLineEditor.new(buffer: ["", "second"], line_index: 0)
    fake.send(:__baslash_hotkey_marker, [7])
    assert_equal ["", "second"], fake.buffer
    refute fake.finished?
  end

  StubBuilder = Struct.new(:slash_registry, :logger)

  # Stand-in for Reline::LineEditor sufficient to exercise our defined
  # methods without driving an actual TTY. Exposes the ivars and helpers
  # the hotkey method uses: @buffer_of_lines, @line_index, current_line,
  # set_current_line, finish. Delegates any __baslash_hotkey_* call to the
  # method defined on Reline::LineEditor at runtime by binding it to self.
  class FakeLineEditor
    attr_reader :byte_pointer

    def initialize(buffer:, line_index:)
      @buffer_of_lines = buffer
      @line_index      = line_index
      @byte_pointer    = 0
      @finished        = false
    end

    def buffer; @buffer_of_lines; end
    def current_line; @buffer_of_lines[@line_index]; end

    def set_current_line(line, ptr = nil)
      @buffer_of_lines[@line_index] = line
      @byte_pointer = ptr || line.bytesize
    end

    def finish; @finished = true; end
    def finished?; @finished; end

    def respond_to_missing?(name, include_private = false)
      Reline::LineEditor.method_defined?(name, true) ||
        Reline::LineEditor.private_method_defined?(name) ||
        super
    end

    def method_missing(name, *args, &blk)
      if Reline::LineEditor.method_defined?(name, true) || Reline::LineEditor.private_method_defined?(name)
        Reline::LineEditor.instance_method(name).bind(self).call(*args, &blk)
      else
        super
      end
    end
  end
end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TESTOPTS="-n /HotkeyInstaller/"`
Expected: `LoadError: cannot load such file -- baslash/hotkey_installer`.

- [x] **Step 3: Write implementation**

```ruby
# lib/baslash/hotkey_installer.rb
# frozen_string_literal: true

require "reline"
require_relative "hotkey_spec"

module Baslash
  # Walk the slash registry; for every entry that carries a hotkey, define
  # a uniquely named instance method on Reline::LineEditor and bind the
  # parsed byte sequence to that method symbol via
  # Reline.core.config.add_default_key_binding.
  #
  # Reline 0.6.3 dispatches a matched key sequence by symbol with
  # __send__(method_symbol) and refuses non-method targets in
  # wrap_method_call (respond_to?(symbol, true) gate). Proc/lambda targets
  # are therefore not viable; per-hotkey defined methods are required.
  module HotkeyInstaller
    METHOD_PREFIX = "__baslash_hotkey_"

    def self.install(builder)
      seen_bytes = {}
      builder.slash_registry.each do |name, entry|
        spec = entry[:hotkey]
        next unless spec
        bytes = Baslash::HotkeySpec.parse(spec) # already validated at register
        if (prev = seen_bytes[bytes])
          builder.logger.warn(
            "hotkey conflict: #{Baslash::HotkeySpec.format(spec)} already bound to /#{prev}; /#{name} overrides"
          )
        end
        seen_bytes[bytes] = name

        define_hotkey_method(name)
        Reline.core.config.add_default_key_binding(bytes, method_name_for(name))
      end
    end

    def self.method_name_for(name)
      :"#{METHOD_PREFIX}#{name}"
    end

    def self.define_hotkey_method(name)
      method_name = method_name_for(name)
      command_line = "/#{name}"
      # Always (re-)define so consecutive installs in tests stay consistent.
      Reline::LineEditor.define_method(method_name) do |_key|
        bol = @buffer_of_lines
        next unless bol.is_a?(Array) && bol.size == 1
        idx = @line_index || 0
        next unless bol[idx].to_s.empty?
        set_current_line(command_line, command_line.bytesize)
        finish
      end
    end
  end
end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TESTOPTS="-n /HotkeyInstaller/"`
Expected: all HotkeyInstaller tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/baslash/hotkey_installer.rb test/test_hotkey_installer_baslash.rb
git commit -m "feat(hotkey): HotkeyInstaller defines per-command method and binds it via Reline"
```

---

## Task 6: format_slash_line renders hotkey suffix

**Files:**
- Modify: `lib/baslash/reline_dialogs.rb`
- Modify: `test/test_reline_dialogs_baslash.rb`

- [x] **Step 1: Write the failing tests**

Append to `test/test_reline_dialogs_baslash.rb` (before the final `end`):

```ruby
  def test_format_slash_line_appends_hotkey_when_present
    item = { name: "/reset", description: "reset state", hotkey: "C-g" }
    line = Baslash::RelineDialogs.format_slash_line(item)
    stripped = line.gsub(/\e\[[0-9;]*m/, "")
    assert_includes stripped, "reset state"
    assert_includes stripped, "(C-g)"
  end

  def test_format_slash_line_no_hotkey_omits_suffix
    item = { name: "/plain", description: "plain" }
    line = Baslash::RelineDialogs.format_slash_line(item)
    stripped = line.gsub(/\e\[[0-9;]*m/, "")
    refute_includes stripped, "()"
    refute_match(/\(C-/, stripped)
  end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TESTOPTS="-n /test_format_slash_line_appends_hotkey|test_format_slash_line_no_hotkey/"`
Expected: 2 fail.

- [x] **Step 3: Update implementation**

In `lib/baslash/reline_dialogs.rb`, replace `format_slash_line`:

```ruby
      def format_slash_line(item)
        name = item[:name].to_s
        desc = item[:description].to_s
        hk   = item[:hotkey].to_s
        hk_suffix = hk.empty? ? "" : "  (#{hk})"
        return "#{name}#{hk_suffix}" if desc.empty?
        pad = [SLASH_NAME_PAD - name.bytesize, 1].max
        "#{name}#{' ' * pad}\e[90m#{desc}#{hk_suffix}\e[0m"
      end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TESTOPTS="-n /RelineDialogs/"`
Expected: all RelineDialogs tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/baslash/reline_dialogs.rb test/test_reline_dialogs_baslash.rb
git commit -m "feat(hotkey): slash-menu dialog shows hotkey suffix"
```

---

## Task 7: /help renders hotkey suffix

**Files:**
- Modify: `lib/baslash/default_commands.rb`
- Modify: `test/test_default_commands_baslash.rb`

- [x] **Step 1: Write the failing tests**

Append to `test/test_default_commands_baslash.rb` (before the final `end`):

```ruby
  def test_help_includes_hotkey_suffix
    extra_registry = Baslash::SlashRegistry.new
    extra_registry.register(:exit, proc {}, description: "exit", hotkey: "C-d")
    extra_registry.register(:reset, proc {}, description: "reset state", hotkey: "C-g")
    extra_registry.register(:plain, proc {}, description: "plain thing")
    Baslash::DefaultCommands.register_help(extra_registry)

    ctx = build_ctx
    extra_registry.lookup(:help)[:body].call([], ctx)
    appended = ctx.appended_texts
    assert(appended.any? { |t| t.include?("/exit")  && t.include?("(C-d)") },
           "expected /exit to carry (C-d) suffix in help, got: #{appended.inspect}")
    assert(appended.any? { |t| t.include?("/reset") && t.include?("(C-g)") },
           "expected /reset to carry (C-g) suffix in help, got: #{appended.inspect}")
    assert(appended.any? { |t| t.include?("/plain") && !t.include?("(C-") },
           "expected /plain to have no hotkey suffix, got: #{appended.inspect}")
  end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TESTOPTS="-n /test_help_includes_hotkey/"`
Expected: fail (no suffix rendered).

- [x] **Step 3: Update implementation**

Replace `lib/baslash/default_commands.rb` `register_help`:

```ruby
    def self.register_help(registry)
      existing = registry.all.map { |name, entry|
        [name.to_s, entry[:description].to_s, entry[:hotkey].to_s].freeze
      }
      existing << ["help", "list slash commands", ""].freeze
      snapshot = Ractor.make_shareable(existing.freeze)
      help_body = Ractor.make_shareable(->(_, ctx) {
        snapshot.each do |name, desc, hotkey|
          suffix =
            if hotkey.empty?
              ""
            else
              " (#{hotkey})"
            end
          line =
            if desc.empty?
              "/#{name}#{suffix}"
            else
              "/#{name}  - #{desc}#{suffix}"
            end
          ctx.display.append(line, style: :dim)
        end
      })
      registry.register(:help, help_body, description: "list slash commands")
    end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TESTOPTS="-n /DefaultCommands/"`
Expected: all DefaultCommands tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/baslash/default_commands.rb test/test_default_commands_baslash.rb
git commit -m "feat(hotkey): /help lists hotkey suffix per command"
```

---

## Task 8: Wire HotkeyInstaller into Runner; require new files

**Files:**
- Modify: `lib/baslash.rb`
- Modify: `lib/baslash/runner.rb`

- [x] **Step 1: Update `lib/baslash.rb`**

Insert `require_relative` lines for the new files. After the existing `require_relative "baslash/slash_dispatcher"` line, add:

```ruby
require_relative "baslash/hotkey_spec"
require_relative "baslash/hotkey_installer"
```

Final top section becomes:

```ruby
require_relative "baslash/version"
require_relative "baslash/style"
require_relative "baslash/title_bar"
require_relative "baslash/transcript"
require_relative "baslash/context"
require_relative "baslash/main_ctx"
require_relative "baslash/display"
require_relative "baslash/slash_registry"
require_relative "baslash/sync_ctx"
require_relative "baslash/slash_dispatcher"
require_relative "baslash/hotkey_spec"
require_relative "baslash/hotkey_installer"
require_relative "baslash/default_commands"
require_relative "baslash/reline_dialogs"
require_relative "baslash/builder"
require_relative "baslash/runner"
```

- [x] **Step 2: Update `lib/baslash/runner.rb`**

Add `require_relative "hotkey_installer"` near the top, then in `Runner.run` insert the installer call **after** `DefaultCommands.register_help(...)` and **before** the first `Display.append`:

```ruby
      install_completion(builder)
      RelineDialogs.install(builder)
      DefaultCommands.register(builder.slash_registry)
      DefaultCommands.register_help(builder.slash_registry)
      Baslash::HotkeyInstaller.install(builder)
```

- [x] **Step 3: Run the full test suite to verify nothing regressed**

Delegate to a `general-purpose` subagent: "Run `bundle exec rake test` from `/Users/bash/dev/src/github.com/bash0C7/baslash` and report only pass/fail and the test count. If anything fails, also report the failing test names." Expected: all tests pass.

- [x] **Step 4: Smoke-check the echo example via pipe**

Run: `printf '/help\n/exit\n' | bundle exec ruby examples/echo_shell.rb`
Expected: output contains `/help` and `/exit` lines (no crashes from the require chain).

- [x] **Step 5: Commit**

```bash
git add lib/baslash.rb lib/baslash/runner.rb
git commit -m "feat(hotkey): wire HotkeyInstaller into Runner after default commands"
```

---

## Task 9: Demonstrative hotkey on /reset in zsh_shell example

**Files:**
- Modify: `examples/zsh_shell/zsh_shell.rb`

- [x] **Step 1: Add hotkey to the existing /reset slash**

Locate the existing `shell.slash(:reset, ...)` block (around line 100) and add `hotkey: "C-g"`:

```ruby
  shell.slash(:reset, description: "reset cwd and env", hotkey: "C-g") do |_args, ctx|
    ctx.state[:cwd].reset
    ctx.state[:env].reset
    ctx.display.append("session reset", style: :result)
  end
```

Also update the `shortcuts_hint` line near it to mention the binding so the user discovers it:

```ruby
  shell.shortcuts_hint "/help for commands · /exit · /pwd · /env · /reset (C-g)"
```

- [x] **Step 2: Smoke-check the example loads**

Run: `printf '/help\n/exit\n' | bundle exec ruby examples/zsh_shell/zsh_shell.rb 2>&1 | head -30`
Expected: output includes `/reset` row and `(C-g)` suffix on it.

- [x] **Step 3: Commit**

```bash
git add examples/zsh_shell/zsh_shell.rb
git commit -m "feat(examples): bind C-g to /reset in zsh_shell to demo hotkeys"
```

---

## Task 10: TTY E2E coverage in 04_tty_e2e.rb

**Files:**
- Modify: `examples/ptyblues_recording/04_tty_e2e.rb`

- [x] **Step 1: Add a hotkey scenario**

Add a new shell script constant near `SLOW_SHELL_SCRIPT`:

```ruby
HOTKEY_SHELL_SCRIPT = <<~RUBY
  # frozen_string_literal: true
  require "baslash"
  Baslash.run do |shell|
    shell.slash(:marker, description: "print hotkey-marker", hotkey: "C-g") do |_args, ctx|
      ctx.display.append("HOTKEY-MARKER-OK", style: :result)
    end
  end
RUBY
```

And in the `Dir.mktmpdir` block, write it out and add a scenario to `scenarios`:

```ruby
hotkey_shell_path = File.join(dir, "hotkey_shell.rb")
File.write(hotkey_shell_path, HOTKEY_SHELL_SCRIPT)
```

```ruby
{
  name: "hotkey C-g from empty buffer dispatches /marker; non-empty buffer ignores",
  spec: <<~SPEC,
    session "hotkey" do
      timeout 10
      spawn argv: ["bundle", "exec", "ruby", "#{hotkey_shell_path}"], cols: 80, rows: 24
      wait 1.0
      # Empty-buffer C-g -> should dispatch /marker
      send "\\u0007"
      wait 0.8
      # Type then C-g -> buffer non-empty, hotkey must be no-op
      send "abc"
      wait 0.3
      send "\\u0007"
      wait 0.5
      # Clear the buffer and exit cleanly
      send "\\u0003"
      wait 0.3
      send "/exit\\r"
      wait 0.5
    end

    expect "hotkey dispatched /marker once from empty buffer" do |captured|
      captured.count("HOTKEY-MARKER-OK") == 1
    end

    expect "exited cleanly" do |captured|
      captured.exit_status == 0
    end
  SPEC
},
```

(Note: `` is `C-g` = BEL byte 7.)

- [x] **Step 2: Verify SpecDSL `captured` API before relying on `count`**

Read `examples/ptyblues_recording/03_spec_e2e.rb` and confirm what methods the SpecDSL `captured` object exposes (`contains?`, `count`, `exit_status`). If `count` is not available, use a `contains?`-based assertion only:

```ruby
expect "hotkey dispatched /marker from empty buffer" do |captured|
  captured.contains?("HOTKEY-MARKER-OK")
end
```

Pick whichever assertion the SpecDSL actually supports before running.

- [x] **Step 3: Run the TTY E2E**

Run: `bundle exec ruby examples/ptyblues_recording/04_tty_e2e.rb`
Expected: all scenarios — including the new hotkey scenario — print `PASS` and the final line is `ALL TTY E2E PASS`.

- [x] **Step 4: Commit**

```bash
git add examples/ptyblues_recording/04_tty_e2e.rb
git commit -m "test(ptyblues): TTY E2E for hotkey dispatch and buffer-empty gate"
```

---

## Task 11: README documentation

**Files:**
- Modify: `README.md`

- [x] **Step 1: Document the `hotkey:` kwarg**

Find the DSL table that documents `shell.slash`, `shell.btw`, `shell.shortcuts_hint`, etc. (around the `btw(&block)` row near line 80). Add `hotkey:` documentation in the same table.

Example row to add (adjust column layout to match existing table style):

```markdown
| `slash(name, description: nil, hotkey: nil, &block)` | Register `/name` slash command. Optional `hotkey:` binds a key (e.g. `"C-g"`, `"M-d"`, `"C-x C-r"`) that dispatches the command from an empty prompt. Calling without a block + `hotkey:` updates an existing command's hotkey only (useful for built-ins like `/exit`). | `(args, ctx)` | — |
```

Then add a short "Hotkeys" sub-section explaining:

```markdown
### Hotkeys

A slash command can be assigned a single-key or chord hotkey via the
`hotkey:` keyword on `shell.slash`. The hotkey fires only when the prompt
buffer is empty; pressing it mid-typing is a no-op.

```ruby
shell.slash(:reset, description: "reset state", hotkey: "C-g") do |_, ctx|
  ctx.state[:cwd].reset
end

# Attach to a built-in command without redefining the body:
shell.slash(:exit, hotkey: "C-d")
```

**Spec grammar:** `C-<letter>`, `M-<letter>`, `M-<digit>`, or a
space-separated chord such as `C-x C-r`. Case-insensitive.

**Reserved (binding raises):** `C-c`, `C-m`, `C-j`, `C-i`, `C-h`.

**Visibility:** registered hotkeys are appended to `/help` rows and to the
slash-menu dialog as a dim ` (C-g)` suffix.
```

- [x] **Step 2: Spot-check README rendering**

Run: `grep -n "hotkey" README.md`
Expected: at least 4-5 lines matching (DSL table row + sub-section heading + examples).

- [x] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): document hotkey: kwarg and Hotkeys section"
```

---

## Task 12: Final full test sweep

- [x] **Step 1: Delegate `bundle exec rake test` to a general-purpose subagent**

Prompt: "From `/Users/bash/dev/src/github.com/bash0C7/baslash`, run `bundle exec rake test` and report only pass/fail and test count. If anything fails, also list failing test names."

Expected: all tests pass; count is `prior_count + (~22 new tests)`.

- [x] **Step 2: Delegate TTY E2E to the same subagent pattern**

Prompt: "Run `bundle exec ruby examples/ptyblues_recording/04_tty_e2e.rb`. Report PASS / FAIL summary lines only."

Expected: `ALL TTY E2E PASS`.

- [x] **Step 3: Sanity-check the example shells one more time via pipe**

```bash
printf '/help\n/exit\n' | bundle exec ruby examples/echo_shell.rb 2>&1 | tail -20
printf '/help\n/exit\n' | bundle exec ruby examples/zsh_shell/zsh_shell.rb 2>&1 | tail -20
```

Expected: /help output lists registered commands and the zsh_shell's /reset row shows `(C-g)`.

- [x] **Step 4: No commit needed** — this task only verifies. If any step fails, fix in a new task and re-run.

---

## Acceptance checklist (matches spec)

- [x] `shell.slash(:foo, hotkey: "C-g")` with a block registers body + key
- [x] `shell.slash(:exit, hotkey: "C-d")` without a block updates an existing entry
- [x] No-block call on unknown name raises `Baslash::HotkeyError`
- [x] `C-c` / `C-m` / `C-j` / `C-i` / `C-h` raise at parse time
- [x] Invalid spec strings raise at `Builder#slash` time (fail-fast)
- [x] Pressing the hotkey on an empty prompt dispatches the command exactly once
- [x] Pressing the hotkey mid-typing or in a multi-line edit is a no-op
- [x] `/help` shows ` (C-g)` suffix for commands with a hotkey
- [x] Slash-menu dialog shows the same suffix
- [x] Duplicate hotkey across two commands emits a `logger.warn`
- [x] Default: no hotkeys bound; baseline behavior unchanged
- [x] `rake test` green; TTY E2E green; example shells smoke-test green
