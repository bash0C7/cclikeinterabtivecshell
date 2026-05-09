# cclikesh — Rendering Overhaul Implementation Plan (Plan 5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the visible "claude-code-style" 3-region UX — info bar above the prompt with spinner, label, and segments — plus dialog primitive and slash-name completion. After this plan, `Cclikesh.run do |shell| ... end` produces a fully-styled interactive shell ready for the irb capstone (Plan 6).

**Architecture:** Pragmatic 3-region: rather than fighting Reline for cursor control, we render the info bar as the **top line of Reline's multi-line prompt**, rebuilt per readline cycle. History prints above (existing behavior), info bar lives in the prompt's first line (`✻ Roosting…  (3m 14s · ↓ 12.4kb)\n> `), input on the bottom line. The spinner frame advances once per readline cycle (acceptable MVP — Plan 6 + irb don't need 60Hz spinner). `Cclikesh::InfoBar` is a pure compose function (testable). `HandlerRegistry#snapshot_info_bar(ctx)` is the F→impl DRb call that runs all info() blocks + spinner_label and rotates idle_phrases. Slash-name completion intercepts `completion_proc` when buffer starts with `/` and has no space, returning registered slash names directly without calling `on_tab`. `ctx.dialog.show / .close` is a thin primitive that uses `Display#append` to print an ASCII-bordered content block to history (no real overlay; satisfies §3.3 surface for irb's optional completion-display alternative).

**Tech Stack:** Ruby 4.0.3, dRuby (UNIX socket) + Rinda::TupleSpace, reline 0.5+ (multi-line prompt support), test-unit 3.6, single-commit-per-task discipline (English conventional commits).

**Position in roadmap:**
- Plan 4 (done): backend extensions (state/hooks/logger/refresh/on_tab/cleanup)
- **Plan 5 (this): rendering — info bar + spinner + idle_phrases + dialog + slash-name completion**
- Plan 6: irb_shell capstone (`IrbEvaluator` / `IrbCompleter` / `ByteCounter` + PTY E2E)

**Single-commit-per-task discipline:** Each task lands as ONE commit (test + impl + wiring). Conventional commit prefix in English.

---

### Task 1: idle_phrases default list — `lib/cclikesh/idle_phrases.txt`

**Files:**
- Create: `lib/cclikesh/idle_phrases.txt`
- Test: none (data file)

**Why:** Spec §6.3 ships 20 default "Roosting / Cogitating / …" words for `:auto` spinner_label cycling. Putting them in a `.txt` file (not Ruby source) keeps the list edit-friendly and lets future `shell.idle_phrases =` overwrites work cleanly.

- [ ] **Step 1: Write the data file**

```
Roosting
Cogitating
Pondering
Galumphing
Schmoozing
Marinating
Percolating
Gestating
Brewing
Conjuring
Munching
Dreaming
Fermenting
Noodling
Simmering
Mulling
Whittling
Composing
Doodling
Mooching
```

(One word per line, no trailing whitespace, final newline.)

- [ ] **Step 2: Commit**

```bash
git add lib/cclikesh/idle_phrases.txt
git commit -m "feat: add default idle_phrases word list"
```

---

### Task 2: Builder DSL — tick_interval + spinner config + spinner_label + idle config + info(name, order:)

**Files:**
- Modify: `lib/cclikesh/builder.rb`
- Test: `test/test_builder.rb`

**Why:** All registration surface from spec §6 + §4.2. Tasks 3-7 consume these. Single Builder commit keeps the DSL surface coherent (one PR review unit).

- [ ] **Step 1: Failing tests in `test/test_builder.rb`**

```ruby
def test_tick_interval_default_and_setter
  builder = Cclikesh::Builder.new
  assert_equal 0.06, builder.tick_interval
  builder.tick_interval = 0.1
  assert_equal 0.1, builder.tick_interval
end

def test_spinner_block_sets_frames_colors_interval
  builder = Cclikesh::Builder.new
  builder.spinner do |s|
    s.frames = %w[A B C]
    s.colors = [:red, :green]
    s.frame_interval = 0.2
  end
  assert_equal %w[A B C], builder.spinner_frames
  assert_equal [:red, :green], builder.spinner_colors
  assert_equal 0.2, builder.spinner_frame_interval
end

def test_spinner_defaults_when_block_not_called
  builder = Cclikesh::Builder.new
  assert_equal %w[✻ ✶ ✷ ✸ ✹], builder.spinner_frames
  assert_equal [:cyan, :magenta], builder.spinner_colors
  assert_equal 0.15, builder.spinner_frame_interval
end

def test_spinner_label_registers_block
  builder = Cclikesh::Builder.new
  builder.spinner_label { |_ctx| "Working" }
  assert_equal "Working", builder.spinner_label_proc.call(:ctx)
end

def test_idle_phrases_default_loaded_from_file
  builder = Cclikesh::Builder.new
  assert_includes builder.idle_phrases, "Roosting"
  assert_includes builder.idle_phrases, "Mooching"
  assert_equal 20, builder.idle_phrases.size
end

def test_idle_phrases_setter_overrides
  builder = Cclikesh::Builder.new
  builder.idle_phrases = %w[Foo Bar]
  assert_equal %w[Foo Bar], builder.idle_phrases
end

def test_idle_phrase_interval_default_and_setter
  builder = Cclikesh::Builder.new
  assert_equal 3.0, builder.idle_phrase_interval
  builder.idle_phrase_interval = 5.0
  assert_equal 5.0, builder.idle_phrase_interval
end

def test_info_registers_block_with_order
  builder = Cclikesh::Builder.new
  builder.info(:elapsed, order: 10) { |_| "1s" }
  builder.info(:tokens,  order: 20) { |_| "↓ 1k" }
  segs = builder.info_segments
  assert_equal [:elapsed, :tokens], segs.map { |name, _, _| name }
  assert_equal "1s",   segs[0][2].call(:ctx)
  assert_equal "↓ 1k", segs[1][2].call(:ctx)
end

def test_info_unspecified_order_uses_registration_order
  builder = Cclikesh::Builder.new
  builder.info(:b) { |_| "b" }
  builder.info(:a, order: 5) { |_| "a" }
  builder.info(:c) { |_| "c" }
  # :a has explicit order=5; :b and :c get registration-time fallback (large numbers)
  segs = builder.info_segments
  assert_equal :a, segs.first[0]
end
```

- [ ] **Step 2: Run — expect FAIL.**

```
bundle exec rake test TEST=test/test_builder.rb
```

- [ ] **Step 3: Implement in `lib/cclikesh/builder.rb`**

Add to `attr_reader`:
```ruby
attr_reader :on_submit_handler, :on_state_change_handler, :slash_handlers,
            :on_start_handlers, :on_quit_handlers,
            :before_submit_handlers, :after_submit_handlers,
            :on_tab_handler, :before_tab_handlers, :after_tab_handlers,
            :logger,
            :spinner_frames, :spinner_colors, :spinner_frame_interval,
            :spinner_label_proc, :idle_phrase_interval
```

Add new accessors:
```ruby
attr_accessor :tick_interval, :idle_phrases
```

In `initialize` (after existing setup):
```ruby
@tick_interval = 0.06
@spinner_frames = %w[✻ ✶ ✷ ✸ ✹]
@spinner_colors = [:cyan, :magenta]
@spinner_frame_interval = 0.15
@spinner_label_proc = nil
@idle_phrases = load_default_idle_phrases
@idle_phrase_interval = 3.0
@info_segments = []  # array of [name_sym, order, block]
@info_registration_counter = 0
```

Add private loader:
```ruby
private

def load_default_idle_phrases
  path = File.expand_path("idle_phrases.txt", __dir__)
  File.readlines(path, chomp: true).reject(&:empty?)
end
```

Add public DSL (after existing methods, restoring `public` if needed):
```ruby
public

class SpinnerConfigurator
  attr_accessor :frames, :colors, :frame_interval
end

def spinner
  configurator = SpinnerConfigurator.new
  configurator.frames = @spinner_frames
  configurator.colors = @spinner_colors
  configurator.frame_interval = @spinner_frame_interval
  yield configurator
  @spinner_frames = configurator.frames
  @spinner_colors = configurator.colors
  @spinner_frame_interval = configurator.frame_interval
end

def spinner_label(&block)
  @spinner_label_proc = block
end

def idle_phrase_interval=(v)
  @idle_phrase_interval = v
end

def info(name, order: nil, &block)
  @info_registration_counter += 1
  effective_order = order || (10_000 + @info_registration_counter)
  @info_segments << [name.to_sym, effective_order, block]
end

def info_segments
  @info_segments.sort_by { |_, order, _| order }
end
```

- [ ] **Step 4: Run — expect PASS.**

```
bundle exec rake test
```

Expected: 144 tests, 0 failures (136 + 8).

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/builder.rb test/test_builder.rb
git commit -m "feat: add Builder DSL for tick_interval, spinner, info, idle_phrases"
```

---

### Task 3: HandlerRegistry — `snapshot_info_bar(ctx)` + `slash_names_starting_with(prefix)`

**Files:**
- Modify: `lib/cclikesh/handler_registry.rb`
- Test: `test/test_handler_registry.rb`

**Why:** F-side InputThread queries impl-side registry over DRb to compose info bar text (spinner frame + label + segments). `slash_names_starting_with` is for Task 7 slash-name completion — fastest to land it here while we're editing the same file.

- [ ] **Step 1: Failing tests in `test/test_handler_registry.rb`**

```ruby
def test_snapshot_info_bar_returns_segments_in_order
  builder = Cclikesh::Builder.new
  builder.info(:elapsed, order: 10) { |_| "1s" }
  builder.info(:tokens,  order: 20) { |_| "↓ 1k" }
  registry = Cclikesh::HandlerRegistry.new(builder)
  snap = registry.snapshot_info_bar(:ctx)
  assert_equal ["1s", "↓ 1k"], snap[:segments]
end

def test_snapshot_info_bar_skips_nil_and_empty_segments
  builder = Cclikesh::Builder.new
  builder.info(:a) { |_| nil }
  builder.info(:b) { |_| "" }
  builder.info(:c) { |_| "ok" }
  registry = Cclikesh::HandlerRegistry.new(builder)
  snap = registry.snapshot_info_bar(:ctx)
  assert_equal ["ok"], snap[:segments]
end

def test_snapshot_info_bar_with_explicit_label_returns_string
  builder = Cclikesh::Builder.new
  builder.spinner_label { |_ctx| "Awaiting" }
  registry = Cclikesh::HandlerRegistry.new(builder)
  snap = registry.snapshot_info_bar(:ctx)
  assert_equal "Awaiting", snap[:spinner_label]
  assert_includes builder.spinner_frames, snap[:spinner_frame]
end

def test_snapshot_info_bar_auto_label_picks_idle_phrase
  builder = Cclikesh::Builder.new
  builder.idle_phrases = %w[ZeroPhrase]
  builder.spinner_label { |_| :auto }
  registry = Cclikesh::HandlerRegistry.new(builder)
  snap = registry.snapshot_info_bar(:ctx)
  assert_equal "ZeroPhrase", snap[:spinner_label]
end

def test_snapshot_info_bar_nil_label_means_spinner_off
  builder = Cclikesh::Builder.new
  builder.spinner_label { |_| nil }
  registry = Cclikesh::HandlerRegistry.new(builder)
  snap = registry.snapshot_info_bar(:ctx)
  assert_nil snap[:spinner_label]
  assert_nil snap[:spinner_frame]
end

def test_snapshot_info_bar_advances_spinner_frame
  builder = Cclikesh::Builder.new
  builder.spinner_label { |_| "Active" }
  registry = Cclikesh::HandlerRegistry.new(builder)
  s1 = registry.snapshot_info_bar(:ctx)[:spinner_frame]
  s2 = registry.snapshot_info_bar(:ctx)[:spinner_frame]
  refute_equal s1, s2
end

def test_snapshot_info_bar_logs_segment_error_and_continues
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  builder.info(:bad)  { |_| raise "seg-boom" }
  builder.info(:good) { |_| "ok" }
  registry = Cclikesh::HandlerRegistry.new(builder)
  snap = registry.snapshot_info_bar(:ctx)
  assert_equal ["ok"], snap[:segments]
  assert_match(/seg-boom/, io.string)
end

def test_slash_names_starting_with_prefix
  builder = Cclikesh::Builder.new
  builder.slash(:reset) { |_, _| }
  builder.slash(:quit)  { |_, _| }
  builder.slash(:q)     { |_, _| }
  registry = Cclikesh::HandlerRegistry.new(builder)
  assert_equal ["/q", "/quit"], registry.slash_names_starting_with("q").sort
  assert_equal ["/reset"],      registry.slash_names_starting_with("re")
  assert_equal [],              registry.slash_names_starting_with("zz")
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement in `lib/cclikesh/handler_registry.rb`**

Add after existing methods:
```ruby
def snapshot_info_bar(ctx)
  log = @builder.logger

  label = compute_spinner_label(ctx, log)
  frame = label ? next_spinner_frame : nil
  segments = compute_info_segments(ctx, log)

  { spinner_frame: frame, spinner_label: label, segments: segments }
end

def slash_names_starting_with(prefix)
  @builder.slash_handlers.keys
    .map(&:to_s)
    .select { |n| n.start_with?(prefix) }
    .sort
    .map { |n| "/#{n}" }
end

private

def compute_spinner_label(ctx, log)
  proc_obj = @builder.spinner_label_proc
  return nil unless proc_obj
  begin
    result = proc_obj.call(ctx)
  rescue => e
    log.error("spinner_label error: #{e.full_message}")
    return nil
  end
  case result
  when nil   then nil
  when :auto then next_idle_phrase
  else result.to_s
  end
end

def next_spinner_frame
  frames = @builder.spinner_frames
  return nil if frames.nil? || frames.empty?
  @spinner_idx = ((@spinner_idx || -1) + 1) % frames.size
  frames[@spinner_idx]
end

def next_idle_phrase
  phrases = @builder.idle_phrases
  return nil if phrases.nil? || phrases.empty?
  @idle_idx = ((@idle_idx || -1) + 1) % phrases.size
  phrases[@idle_idx]
end

def compute_info_segments(ctx, log)
  out = []
  @builder.info_segments.each do |name, _order, block|
    begin
      value = block.call(ctx)
    rescue => e
      log.error("info(:#{name}) error: #{e.full_message}")
      next
    end
    next if value.nil? || value.to_s.empty?
    out << value.to_s
  end
  out
end
```

Note: `private` here ends the public surface. Make sure the existing `def style_definition` and `def logger` (which were before this addition) remain public. Add `public` before them if you reorder, OR add the new methods AFTER `style_definition`/`logger` and put `private` only before the helpers.

Concretely: place the new public method `snapshot_info_bar` and `slash_names_starting_with` BEFORE the existing `def style_definition` line, then put `private` just above `compute_spinner_label`. Existing `style_definition` and `logger` stay public.

- [ ] **Step 4: Run — expect PASS.**

Expected: 152 tests, 0 failures (144 + 8).

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/handler_registry.rb test/test_handler_registry.rb
git commit -m "feat: add HandlerRegistry#snapshot_info_bar + slash_names_starting_with"
```

---

### Task 4: `Cclikesh::InfoBar.compose` — pure renderer

**Files:**
- Create: `lib/cclikesh/info_bar.rb`
- Modify: `lib/cclikesh.rb` (require)
- Test: `test/test_info_bar.rb` (new)

**Why:** Decouple info bar text composition from threading/Reline. Pure function takes the snapshot and returns a styled String. Makes Task 5 InputThread integration trivial.

- [ ] **Step 1: Create test file `test/test_info_bar.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/info_bar"

class TestInfoBar < Test::Unit::TestCase
  def test_returns_empty_when_no_label_no_segments
    out = Cclikesh::InfoBar.compose(spinner_frame: nil, spinner_label: nil, segments: [])
    assert_equal "", out
  end

  def test_renders_spinner_frame_and_label
    out = Cclikesh::InfoBar.compose(spinner_frame: "✻", spinner_label: "Roosting", segments: [])
    assert_match(/✻/, out)
    assert_match(/Roosting/, out)
  end

  def test_renders_label_only_when_no_frame
    out = Cclikesh::InfoBar.compose(spinner_frame: nil, spinner_label: "Awaiting", segments: [])
    refute_match(/✻/, out)
    assert_match(/Awaiting/, out)
  end

  def test_joins_segments_with_dot_separator
    out = Cclikesh::InfoBar.compose(spinner_frame: nil, spinner_label: nil, segments: ["3s", "↓ 1k"])
    assert_match(/3s/, out)
    assert_match(/↓ 1k/, out)
    assert_match(/·/, out)
    assert_match(/\(.+\)/, out)
  end

  def test_label_and_segments_appear_together
    out = Cclikesh::InfoBar.compose(
      spinner_frame: "✻",
      spinner_label: "Roosting",
      segments: ["3s", "↓ 1k"]
    )
    assert_match(/✻.*Roosting/, out)
    assert_match(/Roosting.*\(3s · ↓ 1k\)/, out)
  end

  def test_renders_dim_ansi_for_segments
    out = Cclikesh::InfoBar.compose(spinner_frame: nil, spinner_label: nil, segments: ["3s"])
    # segments wrapped in dim style
    assert_match(/\e\[2m/, out)
    assert_match(/\e\[0m/, out)
  end
end
```

- [ ] **Step 2: Run — expect FAIL (file missing).**

```
bundle exec rake test TEST=test/test_info_bar.rb
```

- [ ] **Step 3: Implement `lib/cclikesh/info_bar.rb`**

```ruby
# frozen_string_literal: true

require_relative "style"

module Cclikesh
  module InfoBar
    def self.compose(spinner_frame:, spinner_label:, segments:)
      label_part = build_label_part(spinner_frame, spinner_label)
      seg_part   = build_segments_part(segments)

      parts = [label_part, seg_part].reject { |p| p.nil? || p.empty? }
      parts.join("  ")
    end

    def self.build_label_part(frame, label)
      return "" if label.nil? || label.empty?
      label_styled = Style.wrap(label, :thinking)
      frame.nil? || frame.empty? ? label_styled : "#{Style.wrap(frame, :thinking)} #{label_styled}"
    end

    def self.build_segments_part(segments)
      return "" if segments.nil? || segments.empty?
      joined = segments.join(" · ")
      "(#{Style.wrap(joined, :dim)})"
    end
  end
end
```

- [ ] **Step 4: Update `lib/cclikesh.rb`**

```ruby
# frozen_string_literal: true

require_relative "cclikesh/version"
require_relative "cclikesh/runner"
require_relative "cclikesh/event_thread"
require_relative "cclikesh/info_bar"

module Cclikesh
  def self.run(&block)
    Runner.run(&block)
  end
end
```

- [ ] **Step 5: Run — expect PASS.**

Expected: 158 tests, 0 failures (152 + 6).

- [ ] **Step 6: Commit**

```bash
git add lib/cclikesh/info_bar.rb lib/cclikesh.rb test/test_info_bar.rb
git commit -m "feat: add InfoBar.compose pure renderer"
```

---

### Task 5: InputThread — multi-line prompt with info bar per readline cycle

**Files:**
- Modify: `lib/cclikesh/input_thread.rb`
- Test: `test/test_input_thread.rb`

**Why:** The actual visible 3-region UX. Each readline call rebuilds the prompt as `<info_bar>\n<base_prompt>` if the info bar is non-empty, otherwise just `<base_prompt>`. Spinner frame advances per call (not per 60ms tick — pragmatic MVP, see plan rationale).

- [ ] **Step 1: Failing tests in `test/test_input_thread.rb`**

```ruby
def test_compose_prompt_returns_base_when_no_info_bar
  fake_registry = Object.new
  fake_registry.define_singleton_method(:snapshot_info_bar) do |_|
    { spinner_frame: nil, spinner_label: nil, segments: [] }
  end
  prompt = Cclikesh::InputThread.compose_prompt("> ", fake_registry, :ctx)
  assert_equal "> ", prompt
end

def test_compose_prompt_includes_info_bar_above_base
  fake_registry = Object.new
  fake_registry.define_singleton_method(:snapshot_info_bar) do |_|
    { spinner_frame: "✻", spinner_label: "Roosting", segments: ["3s"] }
  end
  prompt = Cclikesh::InputThread.compose_prompt("> ", fake_registry, :ctx)
  lines = prompt.split("\n")
  assert_equal 2, lines.size
  assert_match(/Roosting/, lines[0])
  assert_equal "> ", lines[1]
end

def test_compose_prompt_no_registry_returns_base
  prompt = Cclikesh::InputThread.compose_prompt("> ", nil, nil)
  assert_equal "> ", prompt
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement in `lib/cclikesh/input_thread.rb`**

```ruby
# frozen_string_literal: true

require "reline"
require_relative "info_bar"

module Cclikesh
  class InputThread
    def self.install_completion_proc(registry:, ctx:, apply: ->(p) { Reline.completion_proc = p })
      proc = ->(buf) {
        registry.dispatch_tab(buf, buf.bytesize, ctx)
      }
      apply.call(proc)
      proc
    end

    def self.compose_prompt(base_prompt, registry, ctx)
      return base_prompt if registry.nil?
      snap = registry.snapshot_info_bar(ctx)
      bar = InfoBar.compose(
        spinner_frame: snap[:spinner_frame],
        spinner_label: snap[:spinner_label],
        segments:      snap[:segments]
      )
      bar.empty? ? base_prompt : "#{bar}\n#{base_prompt}"
    end

    def self.start(ts, reader:, prompt: "> ", registry: nil, ctx: nil)
      install_completion_proc(registry: registry, ctx: ctx) if registry && ctx

      Thread.new do
        loop do
          quit_tuple = begin
            ts.read([:cmd, :quit], 0)
          rescue Rinda::RequestExpiredError
            nil
          end
          break if quit_tuple

          effective_prompt = compose_prompt(prompt, registry, ctx)
          line = reader.call(effective_prompt)
          payload = line.nil? ? nil : line.chomp
          ts.write([:key, payload])
          break if payload.nil?
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS.**

Expected: 161 tests, 0 failures (158 + 3).

**Verify PTY E2E** still works — the existing PTY tests don't register info() blocks so info bar is empty and prompt collapses to base, behavior unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/input_thread.rb test/test_input_thread.rb
git commit -m "feat: render info bar above prompt via InputThread.compose_prompt"
```

---

### Task 6: `ctx.dialog.show / .close` — primitive backed by Display#append

**Files:**
- Create: `lib/cclikesh/dialog.rb`
- Modify: `lib/cclikesh/context.rb`
- Modify: `lib/cclikesh.rb` (require)
- Test: `test/test_dialog.rb` (new), `test/test_context.rb`

**Why:** Spec §3.3 lists `ctx.dialog.show(content, style:)` and `ctx.dialog.close`. For MVP, dialog is a thin wrapper around `Display#append` that prints an ASCII-bordered block to history. `close` is a no-op (committed-to-history dialogs don't need explicit close). Real overlay rendering deferred until a future plan demands it; irb's tab completion uses Reline's native dialog anyway.

- [ ] **Step 1: Failing tests in `test/test_dialog.rb` (new)**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/dialog"
require "cclikesh/display"
require "cclikesh/tuple_space"

class TestDialog < Test::Unit::TestCase
  def test_show_emits_top_content_lines_and_bottom
    ts = Cclikesh::TupleSpace.new
    display = Cclikesh::Display.new(ts)
    dialog = Cclikesh::Dialog.new(display)
    dialog.show("alpha\nbeta")

    tuples = drain_display_tuples(ts)
    assert_equal 4, tuples.size
    assert_match(/┌/, tuples[0][2])
    assert_match(/alpha/, tuples[1][2])
    assert_match(/beta/, tuples[2][2])
    assert_match(/└/, tuples[3][2])
  end

  def test_show_with_style_passes_style_to_content_lines
    ts = Cclikesh::TupleSpace.new
    display = Cclikesh::Display.new(ts)
    dialog = Cclikesh::Dialog.new(display)
    dialog.show("hello", style: :result)

    tuples = drain_display_tuples(ts)
    content_tuples = tuples.select { |t| t[2].include?("hello") }
    assert_equal 1, content_tuples.size
    assert_equal :result, content_tuples[0][3][:style]
  end

  def test_close_is_noop
    ts = Cclikesh::TupleSpace.new
    display = Cclikesh::Display.new(ts)
    dialog = Cclikesh::Dialog.new(display)
    dialog.close
    assert_raise(Rinda::RequestExpiredError) do
      ts.take([:render, :display_append, nil, nil], 0)
    end
  end

  private

  def drain_display_tuples(ts)
    out = []
    loop { out << ts.take([:render, :display_append, nil, nil], 0) }
  rescue Rinda::RequestExpiredError
    out
  end
end
```

Add to `test/test_context.rb`:
```ruby
def test_context_dialog_returns_dialog_instance
  ts = Cclikesh::TupleSpace.new
  ctx = Cclikesh::Context.new(ts)
  assert_kind_of Cclikesh::Dialog, ctx.dialog
end

def test_context_dialog_writes_through_display
  ts = Cclikesh::TupleSpace.new
  ctx = Cclikesh::Context.new(ts)
  ctx.dialog.show("hi")

  found = []
  loop { found << ts.take([:render, :display_append, nil, nil], 0) }
rescue Rinda::RequestExpiredError
  matched = found.any? { |t| t[2].include?("hi") }
  assert(matched, "dialog content not pushed to display: #{found.inspect}")
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `lib/cclikesh/dialog.rb`**

```ruby
# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class Dialog
    include DRb::DRbUndumped

    def initialize(display)
      @display = display
    end

    def show(content, style: nil)
      lines = content.to_s.split("\n", -1)
      lines.pop if lines.last == ""
      width = (lines.map(&:length).max || 0) + 2

      @display.append("┌#{"─" * width}┐", style: :dim)
      lines.each do |line|
        padded = line.ljust(width - 2)
        @display.append("│ #{padded} │", style: style)
      end
      @display.append("└#{"─" * width}┘", style: :dim)
    end

    def close
      nil
    end
  end
end
```

Note: the test `test_show_with_style_passes_style_to_content_lines` only checks the content line carries the style. The dialog edge characters (`│` framing) carry their own `:dim`. The content gets `style:` passed through. The test compares `:result` against `tuples[2][3][:style]` where index 3 is the opts hash. Note that `Display#append` may wrap content in additional spacing; verify the test asserts what your impl actually emits — adjust line trimming if needed, but keep the style propagation intact.

Look at the test assertion again: `content_tuples[0][3][:style]` where `[3]` is the opts hash. `Display#append(text, style: ..., prompt: ...)` writes `[:render, :display_append, text, opts]` where `opts` is a Hash with `:style`/`:prompt` keys. Confirm by reading `lib/cclikesh/display.rb` if uncertain.

- [ ] **Step 4: Update `lib/cclikesh/context.rb`** — add `dialog` method:

```ruby
require "drb/drb"
require_relative "display"
require_relative "state"
require_relative "dialog"

module Cclikesh
  class Context
    include DRb::DRbUndumped

    def initialize(tuple_space, registry: nil)
      @ts = tuple_space
      @registry = registry
    end

    def display
      @display ||= Display.new(@ts)
    end

    def state
      @state ||= State.new(@ts)
    end

    def dialog
      @dialog ||= Dialog.new(display)
    end

    def logger
      raise "Context has no registry; cannot provide logger" unless @registry
      @registry.logger
    end

    def quit
      @ts.write([:key, nil])
    end

    def refresh
      @ts.write([:cmd, :refresh])
    end
  end
end
```

- [ ] **Step 5: Update `lib/cclikesh.rb`** — add Dialog require:

```ruby
require_relative "cclikesh/dialog"
```

- [ ] **Step 6: Run — expect PASS.**

Expected: 166 tests, 0 failures (161 + 5).

- [ ] **Step 7: Commit**

```bash
git add lib/cclikesh/dialog.rb lib/cclikesh/context.rb lib/cclikesh.rb test/test_dialog.rb test/test_context.rb
git commit -m "feat: add ctx.dialog primitive backed by Display#append"
```

---

### Task 7: Slash-name completion

**Files:**
- Modify: `lib/cclikesh/input_thread.rb`
- Test: `test/test_input_thread.rb`

**Why:** Spec §6.5 — when user types `/` and hasn't entered the command name yet (no space), F should return the registered slash names directly without calling `on_tab`. Once a space appears, treat the rest as args and route to `on_tab` per existing behavior.

- [ ] **Step 1: Failing tests in `test/test_input_thread.rb`**

```ruby
def test_completion_proc_returns_slash_names_when_buffer_starts_with_slash
  ts = Cclikesh::TupleSpace.new
  fake_registry = Object.new
  recorded_dispatch_tab = []
  fake_registry.define_singleton_method(:dispatch_tab) do |buf, pos, ctx|
    recorded_dispatch_tab << [buf, pos, ctx]
    ["should-not-see"]
  end
  fake_registry.define_singleton_method(:slash_names_starting_with) do |prefix|
    case prefix
    when "" then ["/quit", "/reset"]
    when "q" then ["/quit"]
    else []
    end
  end

  proc_returned = nil
  Cclikesh::InputThread.install_completion_proc(
    registry: fake_registry, ctx: :ctx,
    apply: ->(p) { proc_returned = p }
  )

  assert_equal ["/quit", "/reset"], proc_returned.call("/")
  assert_equal ["/quit"],           proc_returned.call("/q")
  assert_empty recorded_dispatch_tab
end

def test_completion_proc_routes_to_dispatch_tab_when_buffer_has_space_after_slash
  ts = Cclikesh::TupleSpace.new
  fake_registry = Object.new
  recorded = []
  fake_registry.define_singleton_method(:dispatch_tab) do |buf, pos, ctx|
    recorded << [buf, pos, ctx]
    ["arg-cand"]
  end
  fake_registry.define_singleton_method(:slash_names_starting_with) do |_|
    flunk "should not be called when buffer has space"
  end

  proc_returned = nil
  Cclikesh::InputThread.install_completion_proc(
    registry: fake_registry, ctx: :ctx_x,
    apply: ->(p) { proc_returned = p }
  )

  result = proc_returned.call("/load file")
  assert_equal ["arg-cand"], result
  assert_equal [["/load file", 10, :ctx_x]], recorded
end

def test_completion_proc_non_slash_buffer_routes_to_dispatch_tab
  fake_registry = Object.new
  recorded = []
  fake_registry.define_singleton_method(:dispatch_tab) do |buf, pos, ctx|
    recorded << [buf, pos, ctx]
    ["non-slash-cand"]
  end
  fake_registry.define_singleton_method(:slash_names_starting_with) do |_|
    flunk "should not be called for non-slash buffer"
  end

  proc_returned = nil
  Cclikesh::InputThread.install_completion_proc(
    registry: fake_registry, ctx: :c,
    apply: ->(p) { proc_returned = p }
  )

  result = proc_returned.call("foo")
  assert_equal ["non-slash-cand"], result
  assert_equal [["foo", 3, :c]], recorded
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Update `lib/cclikesh/input_thread.rb` `#install_completion_proc`**

```ruby
def self.install_completion_proc(registry:, ctx:, apply: ->(p) { Reline.completion_proc = p })
  proc = ->(buf) {
    if buf.start_with?("/") && !buf.include?(" ")
      registry.slash_names_starting_with(buf[1..])
    else
      registry.dispatch_tab(buf, buf.bytesize, ctx)
    end
  }
  apply.call(proc)
  proc
end
```

(Keep the rest of `InputThread` unchanged. The Task 5 tests still pass because their fake registries only stubbed `dispatch_tab` and `snapshot_info_bar`. If the Task 5 test file's existing `test_completion_proc_forwards_to_registry_dispatch_tab` (from Plan 4 Task 9) passes a non-slash buffer, the new logic still routes to `dispatch_tab`.)

- [ ] **Step 4: Run all tests — expect PASS.**

Expected: 169 tests, 0 failures (166 + 3).

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/input_thread.rb test/test_input_thread.rb
git commit -m "feat: complete slash names directly when buffer starts with /"
```

---

### Task 8: example/echo_shell.rb — full info+spinner+idle+dialog demo + PTY E2E

**Files:**
- Modify: `examples/echo_shell.rb`
- Modify: `test/test_e2e_pty.rb`

**Why:** Capstone for Plan 5. Demonstrates info segments, spinner_label `:auto`, idle phrases cycling, dialog via `/dialog` slash, and slash-name completion. PTY E2E asserts the info bar renders visible characters in real terminal output.

- [ ] **Step 1: Update `examples/echo_shell.rb`**

```ruby
# frozen_string_literal: true

require "cclikesh"

start_at = Time.now

Cclikesh.run do |shell|
  shell.define_style(:warn, fg: :yellow, bold: true)

  shell.info(:elapsed, order: 10) do |_ctx|
    sec = (Time.now - start_at).to_i
    m, s = sec.divmod(60)
    m.zero? ? "#{s}s" : "#{m}m #{s}s"
  end

  shell.info(:phase, order: 20) do |ctx|
    ctx.state[:phase].to_s if ctx.state[:phase]
  end

  shell.spinner_label do |ctx|
    case ctx.state[:phase]
    when :working then :auto
    when :awaiting then "Awaiting"
    else nil
    end
  end

  shell.on_submit do |line, ctx|
    ctx.state[:phase] = :working
    ctx.display.append("you said: #{line}", style: :result)
    ctx.state[:phase] = nil
  end

  shell.slash(:slow) do |_args, ctx|
    ctx.state[:phase] = :working
    ctx.display.open_live(style: :thinking) do |slot|
      3.times do |i|
        sleep 0.1
        slot.update("Roosting... #{i + 1}/3")
      end
    end
    ctx.display.append("done", style: :result)
    ctx.state[:phase] = nil
  end

  shell.slash(:dialog) do |args, ctx|
    ctx.dialog.show(args.join(" "), style: :result)
  end

  shell.slash(:warn) do |args, ctx|
    ctx.display.append(args.join(" "), style: :warn)
  end

  shell.slash(:quit) { |_args, ctx| ctx.quit }
  shell.slash(:q)    { |_args, ctx| ctx.quit }
end
```

- [ ] **Step 2: Add a PTY test in `test/test_e2e_pty.rb`**

```ruby
def test_dialog_slash_renders_box
  output = String.new
  pid = nil

  Timeout.timeout(20) do
    master, slave = PTY.open
    pid = spawn(
      "bundle", "exec", "ruby", "-Ilib", ECHO_SHELL,
      in: slave, out: slave, err: slave,
      chdir: PROJECT_ROOT
    )
    slave.close

    wait_for_prompt(master, output, 8)

    master.print "/dialog hello-from-dialog\r"
    sleep 0.5
    master.print "/quit\r"

    drain_until_eof_or_timeout_for(master, output, 5, /hello-from-dialog/)
    Process.wait(pid)
    pid = nil
  end

  assert_match(/┌/, output, "expected dialog top border. Got:\n#{output.inspect}")
  assert_match(/hello-from-dialog/, output)
  assert_match(/└/, output, "expected dialog bottom border")
ensure
  if pid
    begin
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      # already gone
    end
  end
end
```

- [ ] **Step 3: Run all tests — expect PASS.**

```
bundle exec rake test
```

Expected: 170 tests, 0 failures (169 + 1).

The existing `test_echo_then_quit_produces_expected_output` and `test_slow_live_slot_then_quit` from earlier plans continue to pass — `examples/echo_shell.rb` retains the green-styled echo and the `/slow` live slot demo.

- [ ] **Step 4: Manual smoke test (suggested but not gated)**

```
bundle exec ruby -Ilib examples/echo_shell.rb
```

Type:
- `hello` + Enter → green `you said: hello`
- `/slow` + Enter → live slot shows Roosting... ticks, then `done`
- `/q` + space + Tab → slash-name completion shows `/quit`
- `/dialog` `box content` + Enter → ASCII-bordered box prints
- `/quit` + Enter → exits

The info bar is visible above each prompt cycle showing elapsed time and current phase.

- [ ] **Step 5: Commit**

```bash
git add examples/echo_shell.rb test/test_e2e_pty.rb
git commit -m "feat: demo info bar + dialog + slash completion in echo_shell example"
```

---

## Self-Review Checklist (controller fills in before dispatch)

- **Spec coverage:**
  - §3.3 ctx.dialog (Task 6) ✅
  - §4.2 tick_interval (Task 2 builder) ✅
  - §6.1 info area layout `[spinner_frame] [spinner_label]  ([segment1] · [segment2] · ...)` (Task 4 InfoBar) ✅
  - §6.2 spinner DSL with frames/colors/frame_interval, spinner_label `:auto`/String/nil contract (Task 2 + Task 3) ✅
  - §6.3 idle_phrases default file (Task 1), idle_phrase_interval setter (Task 2), `:auto` cycling (Task 3) ✅
  - §6.4 info segments with order, nil/empty skip (Task 2 + Task 3) ✅
  - §6.5 slash-name completion when buffer starts with `/` and no space (Task 7) ✅
  - **NOT covered** (deferred to Plan 6 or beyond): real overlay dialog rendering, 60Hz spinner animation during typing, idle_phrase_interval-driven timed cycling (current impl rotates on each readline call). Document these as known MVP simplifications.
- **Placeholder scan:** All steps have concrete code or exact commands. ✅
- **Type consistency:**
  - `snapshot_info_bar(ctx) → { spinner_frame:, spinner_label:, segments: }` matches Task 3 → Task 5 → Task 4 expectations ✅
  - `slash_names_starting_with(prefix)` returns `Array<String>` with `/`-prefix (Task 3 → Task 7) ✅
  - `info_segments` returns `Array<[name, order, block]>` sorted by order (Task 2 → Task 3) ✅
  - `Cclikesh::Dialog.new(display).show(content, style:)` API matches both test and example (Task 6) ✅
- **Single-commit-per-task:** All 8 tasks land as 1 commit each. ✅

---

## After Plan 5

Plan 6 (irb capstone) is the only remaining plan:
- Create `examples/irb_shell/` with `IrbEvaluator` (Ruby eval with persistent binding), `IrbCompleter` (uses irb/completion), `ByteCounter`
- `irb_shell.rb` entry point per spec §8.2
- PTY E2E that types Ruby expressions and asserts evaluated output
- `format_duration` helper

Plan 5 leaves the framework with full §6 + §3.3 + §4.2 spec coverage minus the deferred MVP simplifications listed above. The framework is feature-complete enough to host irb end-to-end.

## Known MVP simplifications (intentional, document for users)

1. **Spinner animation cadence**: spinner frame advances once per Reline readline cycle (i.e., per user keystroke→Enter cycle), not on a 60Hz timer. During long-running impl callbacks the spinner does NOT animate; live slots cover that role. Future plan can add a tick-driven frame thread if richer UX is needed.
2. **Idle phrase rotation cadence**: idle phrases cycle once per snapshot_info_bar call (i.e., per readline cycle). The `idle_phrase_interval` Builder accessor exists for forward compatibility but is not yet driving rotation. Future plan can wire it to a timer.
3. **Dialog rendering**: dialog is committed to history as an ASCII-bordered block, not rendered as an overlay. Reline's native completion display still fully functions for tab completion. Future plan can add real overlay rendering using ANSI cursor positioning if needed.
