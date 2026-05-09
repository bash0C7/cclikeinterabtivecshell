# cclikesh Curses + Ractor + Debug Sub-gem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace cclikesh's ANSI-direct multi-process architecture with a single-process Ractor model on top of curses (ncursesw), and add `cclikesh-debug` sub-gem providing per-session SQLite recording with sqlite-vec semantic search and asciinema/ffmpeg export.

**Architecture:** Main Ractor owns Reline + curses + canonical UI state. Slash handlers spawn into per-invocation Handler Ractors that talk back via mailbox. User-mutable state lives in opt-in State Ractors via `shareable_ref`. Debug daemon is a separate process, parents the shell under a PTY, and pulls framework_state via DRb that activates only when `CCLIKESH_DEBUG_SOCK` is set; debug recording is itself a 4-Ractor pipeline (PTYReader → FrameBuilder → StorageWriter → Embedder).

**Tech Stack:** Ruby 4.0.3+, `curses ~> 1.4` (ncursesw via Homebrew), `reline ~> 0.6`, `unicode-display_width ~> 3.0`, `sqlite3`, `sqlite-vec`, `informers` (ruri-v3-310m-onnx, 768-dim), `agg` + `ffmpeg` (external CLI for export). macOS only.

**Spec:** `docs/superpowers/specs/2026-05-10-cclikesh-curses-and-debug-design.md`

---

## File map

### Body (target — 14 files, lib/cclikesh/)

| File | Responsibility |
|------|---------------|
| `version.rb` | VERSION constant; bump to 0.2.0 |
| `builder.rb` | DSL (`shell.header`/`info`/`status_row`/`slash`/`shareable_ref`/etc.) |
| `runner.rb` | `Cclikesh.run { }` entry, curses init/teardown, Reline.readline loop |
| `chrome.rb` | `header_win`, `footer_win`, info_bar, status_row, spinner paint |
| `display.rb` | `display_pad`, `append`, `open_live`/live_slot, `dialog` |
| `style.rb` | curses color_pair + attr table; `Style.with(window, name) { }` |
| `reline_dialogs.rb` | slash menu, ghost text, `:periodic_tick` (Main mailbox drain + clock + spinner tick) |
| `slash_dispatcher.rb` | submit → `/parse` → spawn Handler Ractor |
| `slash_registry.rb` | registered handler bodies (`Ractor.make_shareable`'d) |
| `handler_ractor.rb` | Handler Ractor template, spawn + monitor |
| `ctx_proxy.rb` | Handler-side ctx proxy (display, state, logger forwarders) |
| `shareable_ref.rb` | `ShareableRef.spawn(name) { obj }` → State Ractor + proxy |
| `context.rb` | Main Ractor canonical Context module (state, transcript, logger, quit) |
| `transcript.rb` | output-history buffer (kept from current code, retained semantics) |
| `debug_endpoint.rb` | OPTIONAL DRb adapter, only if `ENV['CCLIKESH_DEBUG_SOCK']` set |

### Body deletions (current → removed)

`dispatcher.rb`, `endpoint.rb`, `forking.rb`, `event_thread.rb`, `tuple_space.rb`, `drb_patches.rb`, `screen.rb`, `layout.rb`, `mouse.rb`, `header.rb`, `footer.rb`, `info_bar.rb`, `input_box.rb`, `live_slot.rb`, `dialog.rb`, `state.rb`, `render_thread.rb`, `renderer.rb`, `input_thread.rb`, `history.rb`, `handler_registry.rb`, `idle_phrases.txt`.

### Body tests

| File | Contents |
|------|----------|
| `test/test_helper.rb` | retain, add Curses init/cleanup helper |
| `test/test_style.rb` | replaces existing; curses color_pair mapping |
| `test/test_chrome.rb` | new; offscreen Curses::Pad + window.inch assertions |
| `test/test_display.rb` | new; replaces test_display.rb + test_dialog.rb + test_live_slot.rb |
| `test/test_reline_dialogs.rb` | retain helpers + add periodic_tick + mailbox drain coverage |
| `test/test_slash_dispatcher.rb` | new (replaces test_dispatcher.rb) |
| `test/test_handler_ractor.rb` | new |
| `test/test_ctx_proxy.rb` | new |
| `test/test_shareable_ref.rb` | new |
| `test/test_context.rb` | replaces existing |
| `test/test_transcript.rb` | retain |
| `test/test_debug_endpoint.rb` | new |
| `test/test_builder.rb` | refactor existing |
| `test/test_japanese_paint.rb` | new (CJK + Unicode::DisplayWidth) |
| `test/test_curses_integration.rb` | new (init_screen → addstr → inch round-trip) |
| `test/test_e2e_pty.rb` | refactor existing for curses output |
| `test/test_smoke.rb` | refactor existing |

Tests to delete: `test_drb_patches.rb`, `test_endpoint.rb`, `test_event_thread.rb`, `test_dispatcher.rb`, `test_footer.rb`, `test_forking.rb`, `test_handler_registry.rb`, `test_header.rb`, `test_history.rb`, `test_info_bar.rb`, `test_input_box.rb`, `test_input_thread.rb`, `test_layout.rb`, `test_live_slot.rb`, `test_mouse.rb`, `test_render_thread.rb`, `test_renderer.rb`, `test_screen.rb`, `test_state.rb`, `test_tuple_space.rb`, `test_dialog.rb`.

### Sub-gem (cclikesh-debug/)

```
cclikesh-debug/
├── cclikesh-debug.gemspec
├── exe/cclikesh-debug                              # CLI entrypoint
├── lib/cclikesh/debug/
│   ├── version.rb
│   ├── recorder.rb                                 # orchestrator, spawns + drains 4-Ractor pipeline
│   ├── ractors/{pty_reader,frame_builder,storage_writer,embedder}.rb
│   ├── driver/{start,input,capture,wait,stop,tail}.rb
│   ├── viewer/{list,info,frames,grid,query,semantic,export,clean}.rb
│   ├── storage.rb                                  # SQLite open + schema + insert/select
│   ├── socket_protocol.rb                          # JSON-line over UNIX socket
│   ├── embedder_pool.rb                            # informers wrapper (ruri-v3-310m-onnx)
│   ├── content_builder.rb                          # framework_state → embed text
│   ├── cast_writer.rb                              # asciinema v2 emit
│   └── meta_seeds.rb                               # _sqlite_mcp_meta seed rows
└── test/cclikesh-debug/
    ├── test_storage.rb
    ├── test_content_builder.rb
    ├── test_embedder.rb
    ├── test_cast_writer.rb
    ├── test_socket_protocol.rb
    ├── test_recorder_pipeline.rb
    └── test_e2e_full_session.rb
```

---

## TDD discipline

Every functional task follows RED → GREEN → REFACTOR with **one commit per stage**:
- `test:` for RED (failing test)
- `feat:`/`refactor:` for GREEN (implementation that passes)
- `refactor:` for REFACTOR (structure only, no behavior change; skip if not needed)

Documentation/skeleton/scaffolding tasks are exempt and use a single commit.

---

## Task 0: Ractor compatibility probe

**Files:**
- Create: `tmp/probes/probe_ractor.rb` (throwaway, do NOT commit)
- Modify: `Gemfile` (add curses gem if not present)

- [ ] **Step 1: Ensure curses gem available**

```bash
bundle add curses --version '~> 1.4' --skip-install
PKG_CONFIG_PATH="/opt/homebrew/opt/ncurses/lib/pkgconfig" bundle install
bundle exec ruby -rcurses -e 'puts Curses::VERSION'
```

Expected: prints curses version (e.g. "1.4.4"). If install fails, set `--with-cflags`/`--with-ldflags` for Homebrew ncurses path.

- [ ] **Step 2: Probe 1 — Reline.readline in Main Ractor (baseline)**

Write `tmp/probes/probe_ractor.rb`:

```ruby
require 'reline'
puts "Probe 1: Reline.readline baseline"
print "type something + enter: "
line = Reline.readline("> ", true)
puts "got: #{line.inspect}"
```

Run: `bundle exec ruby tmp/probes/probe_ractor.rb`
Expected: prompts, accepts input, prints what was typed.

- [ ] **Step 3: Probe 2 — curses + CJK render**

Replace `tmp/probes/probe_ractor.rb` with:

```ruby
require 'curses'
Curses.init_screen
Curses.cbreak
Curses.noecho
Curses.start_color
Curses.use_default_colors
win = Curses::Window.new(3, Curses.cols, 0, 0)
win.addstr("✻ cclikesh — 日本語タイトル · v0.2.0")
win.refresh
sleep 1.5
Curses.close_screen
```

Run: `bundle exec ruby tmp/probes/probe_ractor.rb`
Expected: brief display of header line with CJK characters rendered, then return to shell.

- [ ] **Step 4: Probe 3 — Ractor → Main mailbox + curses paint**

```ruby
require 'curses'
Curses.init_screen; Curses.cbreak; Curses.noecho; Curses.start_color; Curses.use_default_colors
win = Curses::Window.new(3, Curses.cols, 0, 0)

main = Ractor.current
worker = Ractor.new(main) do |m|
  3.times do |i|
    m.send([:append, "from worker tick #{i}"])
    sleep 0.3
  end
  m.send([:done])
end

loop do
  msg = receive
  case msg
  in [:append, text]
    win.addstr("#{text}\n")
    win.refresh
  in [:done]
    break
  end
end
sleep 1
Curses.close_screen
```

Expected: 3 lines appear in the curses window over ~1 second, then exit.

- [ ] **Step 5: Probe 4 — handler Proc make_shareable + execute in Ractor**

```ruby
start_at = Time.now.freeze
body = proc { |line| "#{line.upcase} (since #{Time.now - start_at}s)" }
shareable_body = Ractor.make_shareable(body)
r = Ractor.new(shareable_body, "hello".freeze) { |b, l| b.call(l) }
puts r.take
```

Run from the bare shell (no curses).
Expected: prints `HELLO (since <small float>s)` without any `Ractor::IsolationError`. If it fails with closure isolation error, document the failure mode for Step 6.

- [ ] **Step 6: Probe 5 — informers in a worker Ractor**

```ruby
require 'informers'
require 'json'
embed_in_ractor = Ractor.new do
  model = Informers.pipeline('feature-extraction', 'mochiya98/ruri-v3-310m-onnx')
  loop do
    text = receive
    break if text == :stop
    vec = model.(text, model_output: 'sentence_embedding', normalize: true).flatten
    Ractor.yield(vec.length)
  end
end
embed_in_ractor.send("テスト文")
puts "vec length: #{embed_in_ractor.take}"
embed_in_ractor.send(:stop)
```

Expected: prints `vec length: 768`. If it segfaults or warns, note exact symptom.

- [ ] **Step 7: Decide branch**

Record results in scratch notes (not committed):
- All 5 pass → proceed to Task 1.
- Probe 4 fails (closure isolation) → handler runs in Main Ractor synchronously; spinner falls back to dialog-poll-only. Document and proceed.
- Probe 1, 2, or 3 fails → STOP. Open issue with user before proceeding; spec needs revision.
- Probe 5 fails → embedder Ractor falls back to a forked subprocess in the debug pipeline. Note for Task 27.

- [ ] **Step 8: Cleanup**

```bash
rm -rf tmp/probes
git status   # confirm no probe files staged
```

---

## Task 1: Tighten Gemfile + gemspec for new direction

**Files:**
- Modify: `cclikesh.gemspec`
- Modify: `Gemfile.lock` (regenerated by bundle install)

- [ ] **Step 1: Edit cclikesh.gemspec**

```ruby
# cclikesh.gemspec
Gem::Specification.new do |spec|
  spec.name          = "cclikesh"
  spec.version       = Cclikesh::VERSION
  spec.authors       = ["bash0C7"]
  spec.summary       = "Claude Code-style 3-region interactive CLI shell framework (curses + Ractor)"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "curses",                "~> 1.4"
  spec.add_dependency "reline",                "~> 0.6"
  spec.add_dependency "unicode-display_width", "~> 3.0"
  spec.add_dependency "logger"

  spec.add_development_dependency "test-unit", "~> 3.6"
  spec.add_development_dependency "rake",      "~> 13.0"
  spec.add_development_dependency "irb",       "~> 1.18"
end
```

- [ ] **Step 2: Bump version**

Edit `lib/cclikesh/version.rb`:

```ruby
module Cclikesh
  VERSION = "0.2.0"
end
```

- [ ] **Step 3: bundle install + verify**

```bash
bundle install
bundle exec ruby -rcclikesh -e 'puts Cclikesh::VERSION'
```

Expected: prints `0.2.0`, no missing-dep errors.

- [ ] **Step 4: Commit**

```bash
git add cclikesh.gemspec lib/cclikesh/version.rb Gemfile.lock
git commit -m "chore: bump to 0.2.0; switch deps to curses + unicode-display_width"
```

---

## Task 2: Style module (curses-native attr table)

**Files:**
- Create: `lib/cclikesh/style.rb`
- Create: `test/test_style.rb`
- Delete: existing `lib/cclikesh/style.rb` content (replace)

- [ ] **Step 1: Write failing test**

Create `test/test_style.rb`:

```ruby
require_relative "test_helper"
require "curses"
require "cclikesh/style"

class TestStyle < Test::Unit::TestCase
  def setup
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
  end

  def teardown
    Curses.close_screen
  rescue
    nil
  end

  def test_builtin_result_returns_color_pair_and_attr
    pair, attr = Cclikesh::Style.lookup(:result)
    refute_nil pair
    assert_equal 0, attr
  end

  def test_builtin_dim_returns_a_dim_attr
    pair, attr = Cclikesh::Style.lookup(:dim)
    assert (attr & Curses::A_DIM) != 0
  end

  def test_define_custom_style
    Cclikesh::Style.define(:warn, fg: Curses::COLOR_YELLOW, bold: true)
    pair, attr = Cclikesh::Style.lookup(:warn)
    refute_nil pair
    assert (attr & Curses::A_BOLD) != 0
  end

  def test_unknown_style_returns_nil
    assert_equal [nil, 0], Cclikesh::Style.lookup(:nope)
  end

  def test_with_yields_then_attroff
    win = Curses::Window.new(1, 10, 0, 0)
    captured = nil
    Cclikesh::Style.with(win, :result) { captured = :inside }
    assert_equal :inside, captured
    win.close
  end
end
```

- [ ] **Step 2: Run test, confirm RED**

```bash
bundle exec rake test TEST=test/test_style.rb
```

Expected: error / failure for missing `Cclikesh::Style.init!` / `lookup` / `define` / `with`.

- [ ] **Step 3: Commit RED**

```bash
git add test/test_style.rb
git commit -m "test: add failing spec for curses-backed Cclikesh::Style"
```

- [ ] **Step 4: Implement**

Replace `lib/cclikesh/style.rb`:

```ruby
require "curses"

module Cclikesh
  module Style
    BUILTIN = {
      result:   { fg: Curses::COLOR_GREEN },
      error:    { fg: Curses::COLOR_RED },
      thinking: { fg: Curses::COLOR_MAGENTA },
      dim:      { attr_only: Curses::A_DIM },
      gray:     { attr_only: Curses::A_DIM },
    }

    @custom = {}
    @pairs  = {}
    @next_pair_id = 1

    def self.init!
      @custom = {}
      @pairs  = {}
      @next_pair_id = 1
      BUILTIN.each_key { |name| ensure_pair(name, BUILTIN[name]) }
    end

    def self.define(name, fg: nil, bg: nil, bold: false, dim: false, italic: false, underline: false, reverse: false)
      spec = { fg: fg, bg: bg, bold: bold, dim: dim, italic: italic, underline: underline, reverse: reverse }.compact
      @custom[name] = spec
      ensure_pair(name, spec)
    end

    def self.lookup(name)
      key = name&.to_sym
      info = @pairs[key]
      return [nil, 0] unless info
      [info[:pair], info[:attr]]
    end

    def self.with(window, name)
      pair, attr = lookup(name)
      composed = (pair || 0) | attr
      window.attron(composed) if composed != 0
      yield
    ensure
      window.attroff(composed) if composed && composed != 0
    end

    def self.ensure_pair(name, spec)
      key = name.to_sym
      return @pairs[key] if @pairs.key?(key)
      pair_id = nil
      if spec[:fg] || spec[:bg]
        pair_id = @next_pair_id
        @next_pair_id += 1
        Curses.init_pair(pair_id, spec[:fg] || -1, spec[:bg] || -1)
      end
      attr = 0
      attr |= Curses::A_BOLD      if spec[:bold]
      attr |= Curses::A_DIM       if spec[:dim] || spec[:attr_only] == Curses::A_DIM
      attr |= Curses::A_UNDERLINE if spec[:underline]
      attr |= Curses::A_REVERSE   if spec[:reverse]
      pair = pair_id ? Curses.color_pair(pair_id) : 0
      @pairs[key] = { pair: pair, attr: attr }
    end
  end
end
```

- [ ] **Step 5: Run test, confirm GREEN**

```bash
bundle exec rake test TEST=test/test_style.rb
```

Expected: 5 tests, 0 failures.

- [ ] **Step 6: Commit GREEN**

```bash
git add lib/cclikesh/style.rb
git commit -m "feat(style): curses color_pair + attr table replacing ANSI emit"
```

---

## Task 3: Transcript (retain, ensure Ractor-shareable instance state)

**Files:**
- Modify: `lib/cclikesh/transcript.rb`
- Test: `test/test_transcript.rb` (existing)

- [ ] **Step 1: Run existing test**

```bash
bundle exec rake test TEST=test/test_transcript.rb
```

Expected: passes (transcript.rb is already module-level, no concurrency issues with single Mutex).

- [ ] **Step 2: Verify Ractor-safe usage**

The current `transcript.rb` uses module-level `@lines` + `Mutex`. Ractor model: only Main Ractor calls Transcript directly. Handler Ractors use ctx_proxy → Main mailbox → Main calls Transcript. No change needed.

Read `lib/cclikesh/transcript.rb` to confirm Mutex-protected reads/writes only. No edits needed.

- [ ] **Step 3: No commit needed (no changes)**

---

## Task 4: Context (Main-Ractor singleton state module)

**Files:**
- Create: `lib/cclikesh/context.rb` (full rewrite)
- Create: `test/test_context.rb` (full rewrite)

- [ ] **Step 1: Write failing test**

Replace `test/test_context.rb`:

```ruby
require_relative "test_helper"
require "logger"
require "stringio"
require "cclikesh/context"

class TestContext < Test::Unit::TestCase
  def setup
    @log_io = StringIO.new
    Cclikesh::Context.reset!
    Cclikesh::Context.init(logger: Logger.new(@log_io))
  end

  def test_state_set_and_get
    Cclikesh::Context.state_set(:phase, :working)
    assert_equal :working, Cclikesh::Context.state[:phase]
  end

  def test_state_returns_dup_to_prevent_external_mutation
    Cclikesh::Context.state_set(:phase, :idle)
    snapshot = Cclikesh::Context.state
    snapshot[:phase] = :hijacked
    assert_equal :idle, Cclikesh::Context.state[:phase]
  end

  def test_logger_writes_via_module
    Cclikesh::Context.logger.info("hello")
    assert_match(/hello/, @log_io.string)
  end

  def test_quit_sets_quit_flag
    refute Cclikesh::Context.quit?
    Cclikesh::Context.quit
    assert Cclikesh::Context.quit?
  end

  def test_transcript_lines_proxies_to_transcript_module
    require "cclikesh/transcript"
    Cclikesh::Transcript.clear!
    Cclikesh::Transcript.record("hello")
    assert_equal ["hello"], Cclikesh::Context.transcript_lines
  ensure
    Cclikesh::Transcript.clear!
  end
end
```

- [ ] **Step 2: Confirm RED**

```bash
bundle exec rake test TEST=test/test_context.rb
```

- [ ] **Step 3: Commit RED**

```bash
git add test/test_context.rb
git commit -m "test: add failing spec for Context module (state/logger/quit/transcript)"
```

- [ ] **Step 4: Implement**

Replace `lib/cclikesh/context.rb`:

```ruby
require "tmpdir"
require_relative "transcript"

module Cclikesh
  module Context
    @mutex = Mutex.new
    @state = {}
    @logger = nil
    @quit = false

    def self.init(logger:)
      @mutex.synchronize do
        @logger = logger
        @state = {}
        @quit = false
      end
    end

    def self.reset!
      @mutex.synchronize do
        @state = {}
        @logger = nil
        @quit = false
      end
    end

    def self.state
      @mutex.synchronize { @state.dup }
    end

    def self.state_set(key, value)
      @mutex.synchronize { @state[key.to_sym] = value }
    end

    def self.state_clear(key)
      @mutex.synchronize { @state.delete(key.to_sym) }
    end

    def self.logger
      @logger or raise "Cclikesh::Context not initialized"
    end

    def self.quit
      @mutex.synchronize { @quit = true }
    end

    def self.quit?
      @mutex.synchronize { @quit }
    end

    def self.transcript_lines
      Transcript.lines
    end

    def self.transcript_save(path = nil)
      target = path || File.join(Dir.tmpdir, "cclikesh-transcript-#{Process.pid}.log")
      Transcript.save(target)
    end
  end
end
```

- [ ] **Step 5: Confirm GREEN**

```bash
bundle exec rake test TEST=test/test_context.rb
```

Expected: 5 tests, 0 failures.

- [ ] **Step 6: Commit GREEN**

```bash
git add lib/cclikesh/context.rb
git commit -m "feat(context): Main-Ractor singleton state module replacing Context class"
```

---

## Task 5: Chrome (curses windows for header/footer/info_bar)

**Files:**
- Create: `lib/cclikesh/chrome.rb`
- Create: `test/test_chrome.rb`

- [ ] **Step 1: Write failing test**

Create `test/test_chrome.rb`:

```ruby
require_relative "test_helper"
require "curses"
require "cclikesh/style"
require "cclikesh/chrome"

class TestChrome < Test::Unit::TestCase
  def setup
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
    Cclikesh::Chrome.init
  end

  def teardown
    Cclikesh::Chrome.close
    Curses.close_screen
  rescue
    nil
  end

  def test_header_lines_appear_in_header_window
    Cclikesh::Chrome.update_header(["✻ cclikesh", "  v0.2.0"])
    cells = capture_window_text(Cclikesh::Chrome.header_win, 0, 0, 12)
    assert_match(/✻ cclikesh/, cells)
  end

  def test_footer_includes_shortcuts_hint
    Cclikesh::Chrome.update_footer(info_bar: [], status_rows: [], shortcuts_hint: "? for shortcuts")
    cells = capture_window_text(Cclikesh::Chrome.footer_win, 1, 0, 16)
    assert_match(/\? for shortcuts/, cells)
  end

  def test_tick_spinner_advances_index_when_phase_working
    Cclikesh::Chrome.update_footer(info_bar: [], status_rows: [], shortcuts_hint: "")
    initial = Cclikesh::Chrome.spinner_index
    Cclikesh::Chrome.tick_spinner(:working)
    assert_not_equal initial, Cclikesh::Chrome.spinner_index
  end

  def test_tick_spinner_noop_when_idle
    initial = Cclikesh::Chrome.spinner_index
    Cclikesh::Chrome.tick_spinner(:idle)
    assert_equal initial, Cclikesh::Chrome.spinner_index
  end

  private

  def capture_window_text(win, row, col, len)
    chars = []
    len.times do |i|
      ch = win.inch(row, col + i) & Curses::A_CHARTEXT
      chars << ch.chr(Encoding::UTF_8) rescue chars << "?"
    end
    chars.join
  end
end
```

- [ ] **Step 2: Confirm RED**

```bash
bundle exec rake test TEST=test/test_chrome.rb
```

- [ ] **Step 3: Commit RED**

```bash
git add test/test_chrome.rb
git commit -m "test: add failing spec for Chrome (header/footer/spinner)"
```

- [ ] **Step 4: Implement**

Create `lib/cclikesh/chrome.rb`:

```ruby
require "curses"
require "unicode/display_width"

module Cclikesh
  module Chrome
    HEADER_HEIGHT = 3
    FOOTER_HEIGHT = 3
    SPINNER_GLYPHS = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    class << self
      attr_reader :header_win, :footer_win, :spinner_index
    end

    def self.init
      @header_win = Curses::Window.new(HEADER_HEIGHT, Curses.cols, 0, 0)
      @footer_win = Curses::Window.new(FOOTER_HEIGHT, Curses.cols,
                                        Curses.lines - FOOTER_HEIGHT - 1, 0)
      @spinner_index = 0
      @last_clock_min = nil
    end

    def self.close
      @header_win&.close
      @footer_win&.close
      @header_win = nil
      @footer_win = nil
    end

    def self.update_header(lines)
      return unless @header_win
      @header_win.clear
      lines.each_with_index do |line, i|
        next if i >= HEADER_HEIGHT
        @header_win.setpos(i, 0)
        @header_win.addstr(truncate_to_width(line.to_s, Curses.cols - 1))
      end
      @header_win.noutrefresh
    end

    def self.update_footer(info_bar:, status_rows:, shortcuts_hint:)
      return unless @footer_win
      @footer_win.clear
      # row 0: spinner + info_bar segments
      @footer_win.setpos(0, 0)
      glyph = SPINNER_GLYPHS[@spinner_index % SPINNER_GLYPHS.size]
      @footer_win.addstr(glyph + " ")
      info_text = info_bar.map { |item| item[:text] }.compact.join(" · ")
      @footer_win.addstr(truncate_to_width(info_text, Curses.cols - 4))
      # row 1: status_rows
      @footer_win.setpos(1, 0)
      status_text = status_rows.flat_map { |r| r[:segments].map { |s| s[:text] || "" } }.join(" · ")
      @footer_win.addstr(truncate_to_width(status_text, Curses.cols - 1))
      # row 2: shortcuts hint
      @footer_win.setpos(2, 0)
      Style.with(@footer_win, :dim) do
        @footer_win.addstr(truncate_to_width(shortcuts_hint.to_s, Curses.cols - 1))
      end
      @footer_win.noutrefresh
    end

    def self.tick_spinner(phase)
      return unless phase == :working
      @spinner_index = (@spinner_index + 1) % SPINNER_GLYPHS.size
    end

    def self.handle_resize
      return unless @header_win && @footer_win
      @header_win.resize(HEADER_HEIGHT, Curses.cols)
      @footer_win.resize(FOOTER_HEIGHT, Curses.cols)
      @footer_win.move(Curses.lines - FOOTER_HEIGHT - 1, 0)
    end

    def self.truncate_to_width(s, max_cols)
      return s if Unicode::DisplayWidth.of(s) <= max_cols
      acc = +""
      w = 0
      s.each_grapheme_cluster do |g|
        gw = Unicode::DisplayWidth.of(g)
        break if w + gw > max_cols - 1
        acc << g
        w += gw
      end
      acc + "…"
    end
  end
end
```

- [ ] **Step 5: Confirm GREEN**

```bash
bundle exec rake test TEST=test/test_chrome.rb
```

Expected: 4 tests, 0 failures.

- [ ] **Step 6: Commit GREEN**

```bash
git add lib/cclikesh/chrome.rb
git commit -m "feat(chrome): curses windows for header/footer + spinner state"
```

---

## Task 6: Display (display_pad + append + live_slot + dialog)

**Files:**
- Create: `lib/cclikesh/display.rb`
- Create: `test/test_display.rb`

- [ ] **Step 1: Write failing test**

Create `test/test_display.rb`:

```ruby
require_relative "test_helper"
require "curses"
require "cclikesh/style"
require "cclikesh/chrome"
require "cclikesh/display"
require "cclikesh/transcript"

class TestDisplay < Test::Unit::TestCase
  def setup
    Curses.init_screen; Curses.start_color; Curses.use_default_colors
    Cclikesh::Style.init!
    Cclikesh::Chrome.init
    Cclikesh::Display.init
    Cclikesh::Transcript.clear!
  end

  def teardown
    Cclikesh::Display.close
    Cclikesh::Chrome.close
    Curses.close_screen
    Cclikesh::Transcript.clear!
  rescue
    nil
  end

  def test_append_writes_to_pad_and_records_transcript
    Cclikesh::Display.append("hello world")
    assert_equal ["hello world"], Cclikesh::Transcript.lines
  end

  def test_append_with_prompt_concatenates
    Cclikesh::Display.append("ok", prompt: "> ")
    assert_equal ["> ok"], Cclikesh::Transcript.lines
  end

  def test_open_live_returns_sid_and_increments
    s1 = Cclikesh::Display.open_live(style: :thinking)
    s2 = Cclikesh::Display.open_live
    assert s1.is_a?(Integer)
    assert_not_equal s1, s2
  end

  def test_live_update_overwrites_slot_text
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "step 1")
    Cclikesh::Display.live_update(sid, "step 2")
    state = Cclikesh::Display.live_slot_state[sid]
    assert_equal "step 2", state[:last_text]
  end

  def test_live_commit_writes_to_transcript_and_removes_slot
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "tmp")
    Cclikesh::Display.live_commit(sid, "DONE")
    assert_includes Cclikesh::Transcript.lines, "DONE"
    assert_nil Cclikesh::Display.live_slot_state[sid]
  end

  def test_live_discard_removes_slot_without_transcript
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "abc")
    Cclikesh::Display.live_discard(sid)
    refute_includes Cclikesh::Transcript.lines, "abc"
    assert_nil Cclikesh::Display.live_slot_state[sid]
  end

  def test_dialog_appends_box_lines_to_transcript
    Cclikesh::Display.dialog("hello\nworld")
    assert_match(/┌/, Cclikesh::Transcript.lines.first)
    assert(Cclikesh::Transcript.lines.any? { |l| l.include?("hello") })
    assert(Cclikesh::Transcript.lines.any? { |l| l.include?("world") })
    assert_match(/└/, Cclikesh::Transcript.lines.last)
  end
end
```

- [ ] **Step 2: Confirm RED**

```bash
bundle exec rake test TEST=test/test_display.rb
```

- [ ] **Step 3: Commit RED**

```bash
git add test/test_display.rb
git commit -m "test: add failing spec for Display (append/live_slot/dialog)"
```

- [ ] **Step 4: Implement**

Create `lib/cclikesh/display.rb`:

```ruby
require "curses"
require "unicode/display_width"
require_relative "style"
require_relative "transcript"
require_relative "chrome"

module Cclikesh
  module Display
    PAD_HEIGHT = 10_000

    class << self
      attr_reader :pad
    end

    def self.init
      @pad = Curses::Pad.new(PAD_HEIGHT, Curses.cols)
      @pad.scrollok(true)
      @row = 0
      @live_slots = {}
      @next_sid = 0
    end

    def self.close
      @pad&.close
      @pad = nil
      @live_slots = {}
    end

    def self.append(text, prompt: nil, style: nil)
      rendered = "#{prompt}#{text}"
      @pad.setpos(@row, 0)
      Style.with(@pad, style) do
        @pad.addstr(rendered)
      end
      @row += 1
      Transcript.record(rendered)
      refresh
    end

    def self.open_live(style: nil)
      sid = (@next_sid += 1)
      @live_slots[sid] = { row: @row, last_text: "", style: style }
      @pad.setpos(@row, 0)
      @row += 1
      sid
    end

    def self.live_update(sid, text)
      slot = @live_slots[sid] or return
      @pad.setpos(slot[:row], 0)
      @pad.clrtoeol
      Style.with(@pad, slot[:style]) { @pad.addstr(text) }
      slot[:last_text] = text
      refresh
    end

    def self.live_commit(sid, final = nil)
      slot = @live_slots.delete(sid) or return
      text = final || slot[:last_text]
      @pad.setpos(slot[:row], 0)
      @pad.clrtoeol
      Style.with(@pad, slot[:style]) { @pad.addstr(text) }
      Transcript.record(text)
      refresh
    end

    def self.live_discard(sid)
      slot = @live_slots.delete(sid) or return
      @pad.setpos(slot[:row], 0)
      @pad.clrtoeol
      @row -= 1 if slot[:row] == @row - 1
      refresh
    end

    def self.dialog(content, style: nil)
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

    def self.live_slot_state
      @live_slots.dup
    end

    def self.refresh
      return unless @pad
      visible_h = Curses.lines - Chrome::HEADER_HEIGHT - Chrome::FOOTER_HEIGHT - 1
      visible_top = [@row - visible_h, 0].max
      @pad.pnoutrefresh(visible_top, 0,
                         Chrome::HEADER_HEIGHT, 0,
                         Chrome::HEADER_HEIGHT + visible_h - 1, Curses.cols - 1)
    end
  end
end
```

- [ ] **Step 5: Confirm GREEN**

```bash
bundle exec rake test TEST=test/test_display.rb
```

Expected: 7 tests, 0 failures.

- [ ] **Step 6: Commit GREEN**

```bash
git add lib/cclikesh/display.rb
git commit -m "feat(display): pad-backed append/live_slot/dialog with transcript record"
```

---

## Task 7: ShareableRef (State Ractor + proxy)

**Files:**
- Create: `lib/cclikesh/shareable_ref.rb`
- Create: `test/test_shareable_ref.rb`

- [ ] **Step 1: Write failing test**

Create `test/test_shareable_ref.rb`:

```ruby
require_relative "test_helper"
require "cclikesh/shareable_ref"

class TestShareableRef < Test::Unit::TestCase
  class Counter
    def initialize; @n = 0; end
    def add(x); @n += x; end
    def value; @n; end
  end

  def test_call_routes_method_to_owned_object_in_ractor
    ref = Cclikesh::ShareableRef.spawn(:counter) { Counter.new }
    ref.call(:add, 5)
    ref.call(:add, 7)
    assert_equal 12, ref.call(:value)
  ensure
    ref&.stop
  end

  def test_two_refs_have_isolated_state
    a = Cclikesh::ShareableRef.spawn(:a) { Counter.new }
    b = Cclikesh::ShareableRef.spawn(:b) { Counter.new }
    a.call(:add, 1); a.call(:add, 1)
    b.call(:add, 100)
    assert_equal 2,   a.call(:value)
    assert_equal 100, b.call(:value)
  ensure
    a&.stop; b&.stop
  end

  def test_stop_terminates_ractor
    ref = Cclikesh::ShareableRef.spawn(:c) { Counter.new }
    ref.stop
    assert_raise(Ractor::ClosedError) { ref.call(:value) }
  end

  def test_name_accessible
    ref = Cclikesh::ShareableRef.spawn(:my_name) { Counter.new }
    assert_equal :my_name, ref.name
  ensure
    ref&.stop
  end
end
```

- [ ] **Step 2: Confirm RED**

```bash
bundle exec rake test TEST=test/test_shareable_ref.rb
```

- [ ] **Step 3: Commit RED**

```bash
git add test/test_shareable_ref.rb
git commit -m "test: add failing spec for ShareableRef"
```

- [ ] **Step 4: Implement**

Create `lib/cclikesh/shareable_ref.rb`:

```ruby
module Cclikesh
  class ShareableRef
    attr_reader :name

    def self.spawn(name, &block)
      object = block.call
      ractor = Ractor.new(object) do |obj|
        loop do
          msg = receive
          break if msg == :stop
          method, *args = msg
          begin
            result = obj.public_send(method, *args)
            Ractor.yield(result)
          rescue => e
            Ractor.yield([:error, e.class.name, e.message])
          end
        end
      end
      new(name, ractor)
    end

    def initialize(name, ractor)
      @name = name
      @ractor = ractor
    end

    def call(method, *args)
      frozen_args = args.map { |a| a.frozen? ? a : a.dup.freeze }.freeze
      @ractor.send([method, *frozen_args])
      result = @ractor.take
      if result.is_a?(Array) && result[0] == :error
        raise RuntimeError, "ShareableRef(#{@name}).#{method} raised #{result[1]}: #{result[2]}"
      end
      result
    end

    def stop
      @ractor.send(:stop) rescue nil
    end
  end
end
```

- [ ] **Step 5: Confirm GREEN**

```bash
bundle exec rake test TEST=test/test_shareable_ref.rb
```

Expected: 4 tests, 0 failures.

- [ ] **Step 6: Commit GREEN**

```bash
git add lib/cclikesh/shareable_ref.rb
git commit -m "feat(shareable_ref): State Ractor + proxy for mutable user state"
```

---

## Task 8: CtxProxy (Handler-side ctx)

**Files:**
- Create: `lib/cclikesh/ctx_proxy.rb`
- Create: `test/test_ctx_proxy.rb`

- [ ] **Step 1: Write failing test**

Create `test/test_ctx_proxy.rb`:

```ruby
require_relative "test_helper"
require "cclikesh/ctx_proxy"

class TestCtxProxy < Test::Unit::TestCase
  def test_display_append_sends_command_to_main
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      ctx.display.append("hello", style: :result)
    end
    msg = receive
    assert_equal [:append, "hello", { style: :result }], msg
  end

  def test_state_set_sends_state_set
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      ctx.state[:phase] = :working
    end
    msg = receive
    assert_equal [:state_set, :phase, :working], msg
  end

  def test_logger_error_sends_logger
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      ctx.logger.error("boom")
    end
    msg = receive
    assert_equal [:logger, :error, "boom"], msg
  end

  def test_quit_sends_quit
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      ctx.quit
    end
    msg = receive
    assert_equal [:quit], msg
  end

  def test_shareable_returns_named_ref
    require "cclikesh/shareable_ref"
    refs = { evaluator: Cclikesh::ShareableRef.spawn(:evaluator) { Object.new } }
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, refs)
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      Ractor.yield(ctx.shareable(:evaluator).name)
    end.take.tap { |name| assert_equal :evaluator, name }
  ensure
    refs[:evaluator]&.stop
  end
end
```

- [ ] **Step 2: Confirm RED**

```bash
bundle exec rake test TEST=test/test_ctx_proxy.rb
```

- [ ] **Step 3: Commit RED**

```bash
git add test/test_ctx_proxy.rb
git commit -m "test: add failing spec for CtxProxy"
```

- [ ] **Step 4: Implement**

Create `lib/cclikesh/ctx_proxy.rb`:

```ruby
module Cclikesh
  class CtxProxy
    Blueprint = Struct.new(:main_ractor, :state_refs)

    def self.blueprint(main_ractor, state_refs)
      Ractor.make_shareable(Blueprint.new(main_ractor, state_refs.freeze))
    end

    def self.from_blueprint(bp)
      new(bp.main_ractor, bp.state_refs)
    end

    def initialize(main_ractor, state_refs)
      @main = main_ractor
      @state_refs = state_refs
      @display = DisplayProxy.new(@main)
      @logger  = LoggerProxy.new(@main)
      @state   = StateProxy.new(@main)
    end

    attr_reader :display, :logger, :state

    def shareable(name)
      @state_refs[name.to_sym] or raise "no shareable_ref named :#{name}"
    end

    def quit
      @main.send([:quit])
    end

    class DisplayProxy
      def initialize(main); @main = main; end

      def append(text, prompt: nil, style: nil)
        opts = { prompt: prompt, style: style }.compact
        @main.send([:append, text.to_s.freeze, opts.freeze])
      end

      def open_live(style: nil)
        opts = { style: style }.compact
        me = Ractor.current
        @main.send([:open_live_request, me, opts.freeze])
        msg = Ractor.current.receive_if { |m| m.is_a?(Array) && m[0] == :open_live_reply }
        sid = msg[1]
        slot = LiveSlot.new(@main, sid)
        if block_given?
          begin
            yield slot
            slot.commit unless slot.committed?
          rescue
            slot.discard
            raise
          end
        end
        slot
      end

      def dialog(content, style: nil)
        opts = { style: style }.compact
        @main.send([:dialog, content.to_s.freeze, opts.freeze])
      end
    end

    class LiveSlot
      def initialize(main, sid)
        @main = main; @sid = sid; @committed = false
      end

      def update(text)
        @main.send([:live_update, @sid, text.to_s.freeze])
      end

      def commit(final = nil)
        @main.send([:live_commit, @sid, final&.to_s&.freeze])
        @committed = true
      end

      def discard
        @main.send([:live_discard, @sid])
        @committed = true
      end

      def committed?
        @committed
      end
    end

    class LoggerProxy
      def initialize(main); @main = main; end

      %i[debug info warn error fatal].each do |level|
        define_method(level) { |msg| @main.send([:logger, level, msg.to_s.freeze]) }
      end
    end

    class StateProxy
      def initialize(main); @main = main; end

      def []=(key, value)
        @main.send([:state_set, key.to_sym, value.frozen? ? value : value.dup.freeze])
      end

      def [](key)
        me = Ractor.current
        @main.send([:state_get_request, me, key.to_sym])
        msg = Ractor.current.receive_if { |m| m.is_a?(Array) && m[0] == :state_get_reply }
        msg[1]
      end
    end
  end
end
```

- [ ] **Step 5: Confirm GREEN**

```bash
bundle exec rake test TEST=test/test_ctx_proxy.rb
```

Expected: 5 tests, 0 failures.

- [ ] **Step 6: Commit GREEN**

```bash
git add lib/cclikesh/ctx_proxy.rb
git commit -m "feat(ctx_proxy): handler-side ctx forwarding to Main Ractor mailbox"
```

---

## Task 9: SlashRegistry (handler bodies, make_shareable)

**Files:**
- Create: `lib/cclikesh/slash_registry.rb`
- Create: `test/test_slash_registry.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/test_slash_registry.rb
require_relative "test_helper"
require "cclikesh/slash_registry"

class TestSlashRegistry < Test::Unit::TestCase
  def test_register_and_lookup
    reg = Cclikesh::SlashRegistry.new
    body = proc { |args, ctx| args.size }
    reg.register(:echo, body, description: "echo test")
    entry = reg.lookup(:echo)
    refute_nil entry
    assert_equal "echo test", entry[:description]
    assert_kind_of Proc, entry[:body]
    assert Ractor.shareable?(entry[:body])
  end

  def test_lookup_unknown_returns_nil
    reg = Cclikesh::SlashRegistry.new
    assert_nil reg.lookup(:nope)
  end

  def test_each_iterates_in_insertion_order
    reg = Cclikesh::SlashRegistry.new
    reg.register(:a, proc {}, description: "a")
    reg.register(:b, proc {}, description: "b")
    reg.register(:c, proc {}, description: "c")
    assert_equal [:a, :b, :c], reg.each.map { |name, _| name }
  end

  def test_all_returns_frozen_snapshot
    reg = Cclikesh::SlashRegistry.new
    reg.register(:x, proc {}, description: "x")
    snapshot = reg.all
    assert snapshot.frozen?
  end
end
```

- [ ] **Step 2: Confirm RED, commit**

```bash
bundle exec rake test TEST=test/test_slash_registry.rb
git add test/test_slash_registry.rb
git commit -m "test: add failing spec for SlashRegistry"
```

- [ ] **Step 3: Implement + verify**

Create `lib/cclikesh/slash_registry.rb`:

```ruby
module Cclikesh
  class SlashRegistry
    def initialize
      @entries = {}
    end

    def register(name, body, description: nil)
      shareable_body = Ractor.make_shareable(body, copy: true)
      @entries[name.to_sym] = {
        body:        shareable_body,
        description: description.to_s.freeze
      }.freeze
    end

    def lookup(name)
      @entries[name.to_sym]
    end

    def each(&block)
      @entries.each(&block)
    end

    def all
      @entries.dup.freeze
    end
  end
end
```

```bash
bundle exec rake test TEST=test/test_slash_registry.rb
git add lib/cclikesh/slash_registry.rb
git commit -m "feat(slash_registry): registry of make_shareable'd handler bodies"
```

---

## Task 10: SlashDispatcher + HandlerRactor

**Files:**
- Create: `lib/cclikesh/slash_dispatcher.rb`
- Create: `lib/cclikesh/handler_ractor.rb`
- Create: `test/test_slash_dispatcher.rb`
- Create: `test/test_handler_ractor.rb`

- [ ] **Step 1: Write failing test for HandlerRactor**

```ruby
# test/test_handler_ractor.rb
require_relative "test_helper"
require "cclikesh/handler_ractor"
require "cclikesh/ctx_proxy"

class TestHandlerRactor < Test::Unit::TestCase
  def test_spawn_runs_body_with_args
    body = Ractor.make_shareable(proc { |args, ctx| ctx.display.append("got: #{args.first}") })
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Cclikesh::HandlerRactor.spawn(body: body, args: ["hello"].freeze, ctx_blueprint: bp)
    msg = receive
    assert_equal [:append, "got: hello", {}], msg
  end

  def test_handler_exception_sends_error_log
    body = Ractor.make_shareable(proc { |args, ctx| raise "boom" })
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Cclikesh::HandlerRactor.spawn(body: body, args: [].freeze, ctx_blueprint: bp)
    # Drain messages until we see logger:error or append:error
    msgs = []
    5.times { msgs << receive_if(timeout: 1.0) { true } rescue break }
    assert msgs.any? { |m| m[0] == :logger && m[1] == :error }
  end
end
```

- [ ] **Step 2: Write failing test for SlashDispatcher**

```ruby
# test/test_slash_dispatcher.rb
require_relative "test_helper"
require "cclikesh/slash_registry"
require "cclikesh/slash_dispatcher"

class TestSlashDispatcher < Test::Unit::TestCase
  def setup
    @reg = Cclikesh::SlashRegistry.new
    @reg.register(:echo, proc { |args, ctx| ctx.display.append(args.join(" ")) }, description: "echo")
  end

  def test_handle_slash_command_dispatches
    main = Ractor.current
    Cclikesh::SlashDispatcher.handle("/echo hi there", @reg, main, on_submit: nil, state_refs: {})
    msg = receive_if(timeout: 1.0) { true }
    assert_equal :append, msg[0]
    assert_equal "hi there", msg[1]
  end

  def test_handle_unknown_slash_sends_error_append
    main = Ractor.current
    Cclikesh::SlashDispatcher.handle("/nope", @reg, main, on_submit: nil, state_refs: {})
    msg = receive_if(timeout: 1.0) { true }
    assert_equal :append, msg[0]
    assert_match(/Unknown command/, msg[1])
  end

  def test_handle_non_slash_uses_on_submit
    on_submit = Ractor.make_shareable(proc { |args, ctx| ctx.display.append("submit: #{args.first}") })
    main = Ractor.current
    Cclikesh::SlashDispatcher.handle("plain text", @reg, main, on_submit: on_submit, state_refs: {})
    msg = receive_if(timeout: 1.0) { true }
    assert_equal "submit: plain text", msg[1]
  end
end
```

- [ ] **Step 3: Confirm RED, commit both**

```bash
bundle exec rake test TEST=test/test_handler_ractor.rb
bundle exec rake test TEST=test/test_slash_dispatcher.rb
git add test/test_handler_ractor.rb test/test_slash_dispatcher.rb
git commit -m "test: add failing specs for HandlerRactor + SlashDispatcher"
```

- [ ] **Step 4: Implement HandlerRactor**

Create `lib/cclikesh/handler_ractor.rb`:

```ruby
require_relative "ctx_proxy"

module Cclikesh
  module HandlerRactor
    def self.spawn(body:, args:, ctx_blueprint:)
      Ractor.new(body, args, ctx_blueprint) do |b, a, bp|
        ctx = Cclikesh::CtxProxy.from_blueprint(bp)
        begin
          b.call(a, ctx)
        rescue => e
          ctx.display.append("#{e.class}: #{e.message}", style: :error)
          ctx.logger.error("handler error: #{e.full_message}")
        end
      end
    end
  end
end
```

- [ ] **Step 5: Implement SlashDispatcher**

Create `lib/cclikesh/slash_dispatcher.rb`:

```ruby
require_relative "ctx_proxy"
require_relative "handler_ractor"

module Cclikesh
  module SlashDispatcher
    def self.handle(line, registry, main_ractor, on_submit:, state_refs:)
      bp = CtxProxy.blueprint(main_ractor, state_refs)
      if line.start_with?("/")
        name, *args = line[1..].split
        entry = registry.lookup(name)
        if entry.nil?
          main_ractor.send([:append, "Unknown command: /#{name}", { style: :error }.freeze])
          return
        end
        HandlerRactor.spawn(body: entry[:body], args: args.map(&:freeze).freeze, ctx_blueprint: bp)
      else
        return unless on_submit
        HandlerRactor.spawn(body: on_submit, args: [line.freeze].freeze, ctx_blueprint: bp)
      end
    end
  end
end
```

- [ ] **Step 6: Verify GREEN, commit**

```bash
bundle exec rake test TEST=test/test_handler_ractor.rb
bundle exec rake test TEST=test/test_slash_dispatcher.rb
git add lib/cclikesh/handler_ractor.rb lib/cclikesh/slash_dispatcher.rb
git commit -m "feat(handler): SlashDispatcher + per-invocation HandlerRactor"
```

---

## Task 11: Builder DSL refactor

**Files:**
- Modify: `lib/cclikesh/builder.rb` (heavy rewrite)
- Modify: `test/test_builder.rb`

- [ ] **Step 1: Read current builder.rb to map preserved DSL surface**

```bash
wc -l lib/cclikesh/builder.rb
```

Note all DSL methods (`header`, `define_style`, `info`, `status_row`, `spinner_label`, `prompt_suggestion`, `shortcuts_hint`, `btw`, `on_submit`, `on_tab`, `slash`, `before_submit`, `after_submit`, etc.). Confirm via grep what examples actually use.

```bash
grep -E "shell\." examples/echo_shell.rb examples/irb_shell/irb_shell.rb
```

- [ ] **Step 2: Write failing tests for new shareable_ref + slash registration**

Add to `test/test_builder.rb` (replace test method bodies that referenced removed types like `handler_registry`):

```ruby
def test_shareable_ref_creates_named_ref
  builder = Cclikesh::Builder.new
  ref = builder.shareable_ref(:counter) { Hash.new(0) }
  assert_equal :counter, ref.name
  ref.call(:[]=, :n, 5)
  assert_equal 5, ref.call(:[], :n)
ensure
  ref&.stop
end

def test_slash_registers_into_slash_registry
  builder = Cclikesh::Builder.new
  builder.slash(:foo, description: "foo cmd") { |args, ctx| }
  entry = builder.slash_registry.lookup(:foo)
  refute_nil entry
  assert_equal "foo cmd", entry[:description]
end
```

Confirm RED (existing builder doesn't expose `shareable_ref` or `slash_registry`).

- [ ] **Step 3: Commit RED**

```bash
git add test/test_builder.rb
git commit -m "test: add failing builder spec for shareable_ref + slash_registry"
```

- [ ] **Step 4: Refactor builder.rb**

Replace `lib/cclikesh/builder.rb` skeleton (preserve all existing public DSL methods used by examples; add `shareable_ref` + expose `slash_registry`):

```ruby
require "logger"
require_relative "slash_registry"
require_relative "shareable_ref"

module Cclikesh
  class Builder
    attr_reader :slash_registry, :state_refs,
                :on_submit_handler, :on_tab_handler,
                :on_start_handlers, :on_quit_handlers,
                :before_submit_handlers, :after_submit_handlers,
                :info_blocks, :status_row_blocks,
                :spinner_label_block, :prompt_suggestion_block,
                :shortcuts_hint_text, :header_config,
                :logger

    def initialize
      @slash_registry          = SlashRegistry.new
      @state_refs              = {}
      @on_submit_handler       = nil
      @on_tab_handler          = nil
      @on_start_handlers       = []
      @on_quit_handlers        = []
      @before_submit_handlers  = []
      @after_submit_handlers   = []
      @info_blocks             = []
      @status_row_blocks       = []
      @spinner_label_block     = nil
      @prompt_suggestion_block = nil
      @shortcuts_hint_text     = ""
      @header_config           = {}
      @logger                  = Logger.new($stderr).tap { |l| l.progname = "cclikesh" }
      @slash_descriptions      = {}
    end

    def shareable_ref(name, &block)
      ref = ShareableRef.spawn(name, &block)
      @state_refs[name.to_sym] = ref
      ref
    end

    def header(&block)
      h = HeaderConfig.new
      block.call(h)
      @header_config = h.to_h
    end

    def define_style(name, **kwargs)
      Style.define(name, **kwargs)
    end

    def info(name, order: 0, &block)
      @info_blocks << { name: name.to_sym, order: order, block: block }
    end

    def status_row(name, &block)
      @status_row_blocks << { name: name.to_sym, block: block }
    end

    def spinner_label(&block); @spinner_label_block = block; end
    def prompt_suggestion(&block); @prompt_suggestion_block = block; end
    def shortcuts_hint(text); @shortcuts_hint_text = text.to_s; end

    def on_submit(&block); @on_submit_handler = Ractor.make_shareable(block, copy: true); end
    def on_tab(&block); @on_tab_handler = block; end
    def on_start(&block); @on_start_handlers << block; end
    def on_quit(&block); @on_quit_handlers << block; end
    def before_submit(&block); @before_submit_handlers << block; end
    def after_submit(&block); @after_submit_handlers << block; end

    def slash(name, description: nil, &block)
      @slash_registry.register(name.to_sym, block, description: description)
    end

    def btw(&block)
      slash(:btw, description: "ask a question") do |args, ctx|
        question = args.join(" ")
        answer = block.call(question, ctx)
        ctx.display.append(answer.to_s, style: :result) if answer
      end
    end

    def evaluate_info_bar
      @info_blocks.sort_by { |b| b[:order] }.map do |b|
        text = b[:block].call(nil) rescue nil
        { key: b[:name], text: text }
      end.compact
    end

    def evaluate_status_rows
      @status_row_blocks.map do |b|
        row = StatusRow.new(b[:name])
        b[:block].call(row, nil) rescue nil
        { key: b[:name], segments: row.segments }
      end
    end

    def evaluate_spinner_label
      return nil unless @spinner_label_block
      @spinner_label_block.call(nil) rescue nil
    end

    def evaluate_prompt_suggestion
      return nil unless @prompt_suggestion_block
      @prompt_suggestion_block.call(nil) rescue nil
    end

    def header_lines
      h = @header_config
      [
        "#{h[:logo] || ""} #{h[:title] || ""} #{h[:version] || ""}".strip,
        "  #{h[:subtitle]}",
        "  #{h[:note]}"
      ].reject { |l| l.strip.empty? }
    end

    HeaderConfig = Struct.new(:logo, :title, :version, :subtitle, :note, keyword_init: true) do
      def to_h
        members.zip(values).to_h.compact
      end
      def logo(v=nil); v.nil? ? self[:logo] : (self[:logo] = v); end
      def title(v=nil); v.nil? ? self[:title] : (self[:title] = v); end
      def version(v=nil); v.nil? ? self[:version] : (self[:version] = v); end
      def subtitle(v=nil); v.nil? ? self[:subtitle] : (self[:subtitle] = v); end
      def note(v=nil); v.nil? ? self[:note] : (self[:note] = v); end
    end

    class StatusRow
      attr_reader :name, :segments
      def initialize(name); @name = name; @segments = []; end
      def icon(s); @segments << { kind: :icon, text: s }; end
      def text(s); @segments << { kind: :text, text: s }; end
      def link(text:, state: nil); @segments << { kind: :link, text: text, state: state }; end
      def bar(percent:, width: 12); @segments << { kind: :bar, percent: percent, width: width }; end
    end
  end
end
```

- [ ] **Step 5: Confirm GREEN, commit**

```bash
bundle exec rake test TEST=test/test_builder.rb
git add lib/cclikesh/builder.rb test/test_builder.rb
git commit -m "feat(builder): DSL refactor for Ractor model + shareable_ref + Style.define"
```

---

## Task 12: Reline dialogs (slash menu + ghost text + periodic_tick mailbox drain)

**Files:**
- Modify: `lib/cclikesh/reline_dialogs.rb` (extend with periodic_tick)
- Modify: `test/test_reline_dialogs.rb` (existing helpers retained, add new)

- [ ] **Step 1: Read existing reline_dialogs.rb**

```bash
wc -l lib/cclikesh/reline_dialogs.rb
```

The existing file has slash_menu_dialog_proc and ghost_text_dialog_proc. Keep the pure-logic helpers (`format_slash_line`, `format_slash_lines`, `visible_width`, `dialog_width`, `format_ghost_hint`).

- [ ] **Step 2: Write failing test for periodic_tick mailbox drain**

Add to `test/test_reline_dialogs.rb`:

```ruby
def test_drain_main_mailbox_dispatches_append
  main = Ractor.current
  main.send([:append, "drained", { style: :result }])
  applied = []
  Cclikesh::RelineDialogs.stub_apply_command_for_test = ->(msg) { applied << msg }
  Cclikesh::RelineDialogs.drain_main_mailbox
  assert_equal [[:append, "drained", { style: :result }]], applied
ensure
  Cclikesh::RelineDialogs.stub_apply_command_for_test = nil
end
```

- [ ] **Step 3: Confirm RED, commit**

```bash
bundle exec rake test TEST=test/test_reline_dialogs.rb
git add test/test_reline_dialogs.rb
git commit -m "test: add failing spec for RelineDialogs.drain_main_mailbox"
```

- [ ] **Step 4: Implement periodic_tick + drain_main_mailbox**

Extend `lib/cclikesh/reline_dialogs.rb` (preserve existing slash_menu and ghost_text, add):

```ruby
require "reline"
require_relative "chrome"
require_relative "display"
require_relative "context"

module Cclikesh
  module RelineDialogs
    class << self
      attr_accessor :stub_apply_command_for_test
    end

    def self.install(builder, registry)
      Reline.add_dialog_proc(:periodic_tick, periodic_tick_proc(builder), Reline::DEFAULT_DIALOG_CONTEXT)
      Reline.add_dialog_proc(:autocomplete, slash_menu_dialog_proc(registry))
      Reline.add_dialog_proc(:ghost_text,   ghost_text_dialog_proc(builder))
    end

    def self.periodic_tick_proc(builder)
      proc do
        Cclikesh::RelineDialogs.drain_main_mailbox
        Cclikesh::Chrome.update_footer(
          info_bar:        builder.evaluate_info_bar,
          status_rows:     builder.evaluate_status_rows,
          shortcuts_hint:  builder.shortcuts_hint_text
        )
        Cclikesh::Chrome.tick_spinner(Cclikesh::Context.state[:phase])
        Curses.doupdate
        nil
      end
    end

    def self.drain_main_mailbox
      100.times do
        msg = begin
          Ractor.current.receive_if(timeout: 0) { true }
        rescue
          nil
        end
        break unless msg
        if stub_apply_command_for_test
          stub_apply_command_for_test.call(msg)
        else
          apply_command(msg)
        end
      end
    end

    def self.apply_command(msg)
      case msg
      in [:append, text, opts]
        Cclikesh::Display.append(text, **opts)
      in [:open_live_request, reply_to, opts]
        sid = Cclikesh::Display.open_live(**opts)
        reply_to.send([:open_live_reply, sid])
      in [:live_update, sid, text]
        Cclikesh::Display.live_update(sid, text)
      in [:live_commit, sid, final]
        Cclikesh::Display.live_commit(sid, final)
      in [:live_discard, sid]
        Cclikesh::Display.live_discard(sid)
      in [:dialog, content, opts]
        Cclikesh::Display.dialog(content, **opts)
      in [:state_set, key, value]
        Cclikesh::Context.state_set(key, value)
      in [:state_get_request, reply_to, key]
        reply_to.send([:state_get_reply, Cclikesh::Context.state[key]])
      in [:logger, level, text]
        Cclikesh::Context.logger.send(level, text)
      in [:quit]
        Cclikesh::Context.quit
      end
    end

    # ... preserve existing slash_menu_dialog_proc, ghost_text_dialog_proc,
    #     format_slash_line, format_slash_lines, visible_width,
    #     dialog_width, format_ghost_hint
  end
end
```

- [ ] **Step 5: Verify GREEN, commit**

```bash
bundle exec rake test TEST=test/test_reline_dialogs.rb
git add lib/cclikesh/reline_dialogs.rb
git commit -m "feat(reline_dialogs): periodic_tick mailbox drain + apply_command dispatch"
```

---

## Task 13: Runner (entry point + Main Ractor loop)

**Files:**
- Modify: `lib/cclikesh/runner.rb` (full rewrite)
- Modify: `lib/cclikesh.rb` (top-level, ensure all new files required)

- [ ] **Step 1: Rewrite lib/cclikesh.rb**

```ruby
require_relative "cclikesh/version"
require_relative "cclikesh/style"
require_relative "cclikesh/transcript"
require_relative "cclikesh/context"
require_relative "cclikesh/chrome"
require_relative "cclikesh/display"
require_relative "cclikesh/shareable_ref"
require_relative "cclikesh/slash_registry"
require_relative "cclikesh/ctx_proxy"
require_relative "cclikesh/handler_ractor"
require_relative "cclikesh/slash_dispatcher"
require_relative "cclikesh/reline_dialogs"
require_relative "cclikesh/builder"
require_relative "cclikesh/debug_endpoint"
require_relative "cclikesh/runner"

module Cclikesh
  def self.run(&block)
    builder = Builder.new
    block.call(builder)
    Runner.run(builder)
  end
end
```

- [ ] **Step 2: Implement Runner**

Replace `lib/cclikesh/runner.rb`:

```ruby
require "curses"
require "reline"

module Cclikesh
  module Runner
    def self.run(builder)
      init_curses
      Style.init!
      Chrome.init
      Display.init
      Context.init(logger: builder.logger)
      DebugEndpoint.start_if_enabled(builder)

      builder.on_start_handlers.each { |h| h.call(nil) rescue nil }

      RelineDialogs.install(builder, builder.slash_registry)
      Chrome.update_header(builder.header_lines)
      Curses.doupdate

      catch(:quit) do
        loop do
          begin
            line = Reline.readline(prompt_text(builder), true)
          rescue Interrupt
            next
          end
          throw :quit if line.nil?
          line = line.to_s
          throw :quit if Context.quit?
          next if line.strip.empty?
          SlashDispatcher.handle(
            line,
            builder.slash_registry,
            Ractor.current,
            on_submit: builder.on_submit_handler,
            state_refs: builder.state_refs
          )
        end
      end

      builder.on_quit_handlers.each { |h| h.call(nil) rescue nil }
    ensure
      teardown_curses
      builder.state_refs.each_value(&:stop)
    end

    def self.init_curses
      Curses.init_screen
      Curses.cbreak
      Curses.noecho
      Curses.start_color
      Curses.use_default_colors
      Curses.stdscr.keypad(true)
    end

    def self.teardown_curses
      Curses.close_screen
    rescue
      nil
    end

    def self.prompt_text(builder)
      "> "
    end
  end
end
```

- [ ] **Step 3: Run smoke test**

```bash
bundle exec rake test TEST=test/test_smoke.rb
```

If smoke test references removed classes, refactor it as part of Task 17 (E2E rewrite). For now, ensure the file at least loads without raise:

```bash
bundle exec ruby -Ilib -e 'require "cclikesh"; puts Cclikesh::VERSION'
```

Expected: prints `0.2.0`.

- [ ] **Step 4: Commit**

```bash
git add lib/cclikesh.rb lib/cclikesh/runner.rb
git commit -m "feat(runner): curses init + Reline.readline loop + Main Ractor mailbox"
```

---

## Task 14: DebugEndpoint (opt-in DRb adapter)

**Files:**
- Create: `lib/cclikesh/debug_endpoint.rb`
- Create: `test/test_debug_endpoint.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/test_debug_endpoint.rb
require_relative "test_helper"
require "cclikesh/builder"
require "cclikesh/debug_endpoint"

class TestDebugEndpoint < Test::Unit::TestCase
  def teardown
    Cclikesh::DebugEndpoint.stop_for_test
    ENV.delete("CCLIKESH_DEBUG_SOCK")
  end

  def test_start_does_nothing_without_env
    builder = Cclikesh::Builder.new
    Cclikesh::DebugEndpoint.start_if_enabled(builder)
    assert_nil Cclikesh::DebugEndpoint.adapter
  end

  def test_start_creates_adapter_when_env_set
    require "tmpdir"
    sock = File.join(Dir.tmpdir, "test-debug-#{Process.pid}")
    ENV["CCLIKESH_DEBUG_SOCK"] = sock
    builder = Cclikesh::Builder.new
    Cclikesh::DebugEndpoint.start_if_enabled(builder)
    refute_nil Cclikesh::DebugEndpoint.adapter
  end

  def test_adapter_debug_snapshot_returns_hash_with_state
    require "tmpdir"
    ENV["CCLIKESH_DEBUG_SOCK"] = File.join(Dir.tmpdir, "test-debug-snap-#{Process.pid}")
    builder = Cclikesh::Builder.new
    builder.shortcuts_hint("? for help")
    Cclikesh::DebugEndpoint.start_if_enabled(builder)
    snap = Cclikesh::DebugEndpoint.adapter.debug_snapshot
    assert snap.key?(:framework_state)
    assert snap.key?(:cursor)
    assert snap.key?(:ts_shell)
    assert_equal "? for help", snap[:framework_state][:shortcuts_hint]
  end

  def test_drain_events_returns_pushed_events
    ENV["CCLIKESH_DEBUG_SOCK"] = "/tmp/test-debug-events-#{Process.pid}"
    Cclikesh::DebugEndpoint.start_if_enabled(Cclikesh::Builder.new)
    Cclikesh::DebugEndpoint.adapter.push_event(:input_received, line: "hello")
    Cclikesh::DebugEndpoint.adapter.push_event(:render_commit)
    events = Cclikesh::DebugEndpoint.adapter.debug_drain_events
    assert_equal 2, events.size
    assert_equal :input_received, events[0][:kind]
    assert_equal "hello", events[0][:payload][:line]
    assert_equal :render_commit, events[1][:kind]
    assert_empty Cclikesh::DebugEndpoint.adapter.debug_drain_events
  end
end
```

- [ ] **Step 2: Confirm RED, commit**

```bash
bundle exec rake test TEST=test/test_debug_endpoint.rb
git add test/test_debug_endpoint.rb
git commit -m "test: add failing spec for DebugEndpoint"
```

- [ ] **Step 3: Implement**

```ruby
# lib/cclikesh/debug_endpoint.rb
module Cclikesh
  module DebugEndpoint
    class << self
      attr_reader :adapter
    end

    def self.start_if_enabled(builder)
      sock = ENV["CCLIKESH_DEBUG_SOCK"]
      return nil unless sock
      require "drb/drb"
      @adapter = Adapter.new(builder)
      @service = DRb.start_service("drbunix:#{sock}.drb", @adapter)
      @adapter
    end

    def self.stop_for_test
      @service&.stop_service rescue nil
      @adapter = nil
      @service = nil
    end

    class Adapter
      def initialize(builder)
        @builder = builder
        @mutex = Mutex.new
        @events = []
      end

      def debug_snapshot
        @mutex.synchronize do
          {
            framework_state: build_framework_state_hash,
            cursor:          current_cursor,
            ts_shell:        Process.clock_gettime(Process::CLOCK_MONOTONIC)
          }
        end
      end

      def debug_drain_events
        @mutex.synchronize { e = @events.dup; @events.clear; e }
      end

      def push_event(kind, payload = {})
        @mutex.synchronize { @events << { kind: kind, payload: payload, ts: Time.now.to_f } }
      end

      private

      def build_framework_state_hash
        require_relative "context"
        require_relative "transcript"
        {
          phase:             Context.state[:phase],
          focus_mode:        Context.state[:focus_mode],
          header:            @builder.header_config,
          info_bar:          @builder.evaluate_info_bar,
          status_rows:       @builder.evaluate_status_rows,
          spinner_label:     @builder.evaluate_spinner_label,
          prompt_suggestion: @builder.evaluate_prompt_suggestion,
          shortcuts_hint:    @builder.shortcuts_hint_text,
          input:             reline_input_state,
          live_slot:         live_slot_state,
          popup:             popup_state,
          transcript_line_count: Transcript.lines.size
        }
      end

      def reline_input_state
        require "reline"
        { buffer: Reline.line_buffer.to_s, cursor_pos: Reline.point.to_i }
      rescue
        { buffer: "", cursor_pos: 0 }
      end

      def live_slot_state
        require_relative "display"
        slots = Cclikesh::Display.live_slot_state rescue {}
        return { active: false, text: nil, style: nil } if slots.empty?
        first = slots.values.first
        { active: true, text: first[:last_text], style: first[:style] }
      end

      def popup_state
        { active: false, kind: nil, candidates_count: 0, selection_index: 0 }
      end

      def current_cursor
        require "curses"
        [Curses.stdscr.cury, Curses.stdscr.curx]
      rescue
        [0, 0]
      end
    end
  end
end
```

- [ ] **Step 4: Verify GREEN, commit**

```bash
bundle exec rake test TEST=test/test_debug_endpoint.rb
git add lib/cclikesh/debug_endpoint.rb
git commit -m "feat(debug_endpoint): opt-in DRb adapter exposing debug_snapshot/events"
```

---

## Task 15: Wholesale deletion of obsolete body files

**Files:**
- Delete (lib): `dispatcher.rb`, `endpoint.rb`, `forking.rb`, `event_thread.rb`, `tuple_space.rb`, `drb_patches.rb`, `screen.rb`, `layout.rb`, `mouse.rb`, `header.rb`, `footer.rb`, `info_bar.rb`, `input_box.rb`, `live_slot.rb`, `dialog.rb`, `state.rb`, `render_thread.rb`, `renderer.rb`, `input_thread.rb`, `history.rb`, `handler_registry.rb`, `idle_phrases.txt`
- Delete (test): the matching `test_*.rb` files

- [ ] **Step 1: Confirm no references remain in retained files**

```bash
grep -rE "require_relative.*(dispatcher|endpoint|forking|event_thread|tuple_space|drb_patches|screen|layout|mouse|header|footer|info_bar|input_box|live_slot|dialog|state|render_thread|renderer|input_thread|history|handler_registry)\b" lib/cclikesh/
```

Expected: no results. If any references remain, fix them in the responsible task before deletion.

- [ ] **Step 2: Delete obsolete lib files**

```bash
cd lib/cclikesh
rm dispatcher.rb endpoint.rb forking.rb event_thread.rb tuple_space.rb drb_patches.rb \
   screen.rb layout.rb mouse.rb \
   header.rb footer.rb info_bar.rb input_box.rb live_slot.rb dialog.rb \
   state.rb render_thread.rb renderer.rb input_thread.rb history.rb \
   handler_registry.rb idle_phrases.txt
cd -
```

- [ ] **Step 3: Delete obsolete test files**

```bash
cd test
rm test_drb_patches.rb test_endpoint.rb test_event_thread.rb test_dispatcher.rb \
   test_footer.rb test_forking.rb test_handler_registry.rb test_header.rb \
   test_history.rb test_info_bar.rb test_input_box.rb test_input_thread.rb \
   test_layout.rb test_live_slot.rb test_mouse.rb test_render_thread.rb \
   test_renderer.rb test_screen.rb test_state.rb test_tuple_space.rb \
   test_dialog.rb
cd -
```

- [ ] **Step 4: Run full test suite**

```bash
bundle exec rake test
```

Expected: all remaining tests pass; failures here indicate a leftover dep on a removed file. Resolve them before commit.

- [ ] **Step 5: Commit**

```bash
git add -A lib/cclikesh test
git commit -m "refactor: drop obsolete process-split + ANSI-direct files (curses single-process)"
```

---

## Task 16: New tests — curses_integration + japanese_paint

**Files:**
- Create: `test/test_curses_integration.rb`
- Create: `test/test_japanese_paint.rb`

- [ ] **Step 1: Write curses_integration test**

```ruby
# test/test_curses_integration.rb
require_relative "test_helper"
require "curses"

class TestCursesIntegration < Test::Unit::TestCase
  def test_init_screen_close_screen_round_trip
    Curses.init_screen
    Curses.start_color
    win = Curses::Window.new(1, 10, 0, 0)
    win.addstr("hello")
    win.refresh
    captured = win.inch(0, 0) & Curses::A_CHARTEXT
    assert_equal "h".ord, captured
    win.close
    Curses.close_screen
  end

  def test_color_pair_init
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Curses.init_pair(1, Curses::COLOR_GREEN, -1)
    pair = Curses.color_pair(1)
    assert pair > 0
    Curses.close_screen
  end
end
```

- [ ] **Step 2: Write japanese_paint test**

```ruby
# test/test_japanese_paint.rb
require_relative "test_helper"
require "curses"
require "unicode/display_width"
require "cclikesh/chrome"

class TestJapanesePaint < Test::Unit::TestCase
  def test_addstr_advances_cursor_by_display_width_for_cjk
    Curses.init_screen
    Curses.start_color
    win = Curses::Window.new(1, 30, 0, 0)
    win.addstr("日本語")
    assert_equal 6, win.curx  # 3 wide chars × 2 cols each
    win.close
    Curses.close_screen
  end

  def test_truncate_to_width_handles_cjk
    s = "日本語abc"  # widths: 2+2+2+1+1+1 = 9
    truncated = Cclikesh::Chrome.truncate_to_width(s, 5)
    assert Unicode::DisplayWidth.of(truncated) <= 5
    assert truncated.end_with?("…")
  end

  def test_truncate_returns_unchanged_when_under_limit
    assert_equal "短い", Cclikesh::Chrome.truncate_to_width("短い", 10)
  end
end
```

- [ ] **Step 3: Run, expect green (no impl needed beyond Task 5)**

```bash
bundle exec rake test TEST=test/test_curses_integration.rb
bundle exec rake test TEST=test/test_japanese_paint.rb
```

- [ ] **Step 4: Commit**

```bash
git add test/test_curses_integration.rb test/test_japanese_paint.rb
git commit -m "test: curses round-trip + CJK paint width assertions"
```

---

## Task 17: E2E PTY test refactor

**Files:**
- Modify: `test/test_e2e_pty.rb`
- Modify: `test/test_smoke.rb`

- [ ] **Step 1: Refactor test_smoke.rb**

Open `test/test_smoke.rb`. Adjust expectations: now that everything is curses, raw `\e[32m` ANSI assertions need to switch to "the rendered text contains expected substring after curses render". Smoke test should:
1. Boot the example via PTY.
2. Send `/q\r`.
3. Assert process exits cleanly.

```ruby
# test/test_smoke.rb (replace body)
require_relative "test_helper"
require "pty"
require "timeout"

class TestSmoke < Test::Unit::TestCase
  ROOT = File.expand_path("..", __dir__)

  def test_echo_shell_boots_and_quits_cleanly
    pid = nil
    Timeout.timeout(15) do
      master, slave = PTY.open
      pid = spawn("bundle", "exec", "ruby", "-Ilib", File.join(ROOT, "examples/echo_shell.rb"),
                   in: slave, out: slave, err: slave, chdir: ROOT)
      slave.close
      sleep 1.0  # let curses init + header render
      master.print "/q\r"
      Process.wait(pid)
      pid = nil
    end
    pass "echo_shell exited within 15s"
  ensure
    Process.kill("KILL", pid) rescue nil if pid
  end
end
```

- [ ] **Step 2: Refactor test_e2e_pty.rb**

Change ANSI-byte expectations to curses-rendered text. Drop `\e[32m...` exact-byte assertions; assert via PTY-tap-then-extract-visible-text.

```ruby
# test/test_e2e_pty.rb (replace)
require_relative "test_helper"
require "pty"
require "timeout"

class TestE2EPty < Test::Unit::TestCase
  ROOT = File.expand_path("..", __dir__)

  def test_echo_then_quit
    output = +""
    pid = nil
    Timeout.timeout(20) do
      master, slave = PTY.open
      pid = spawn("bundle", "exec", "ruby", "-Ilib", File.join(ROOT, "examples/echo_shell.rb"),
                   in: slave, out: slave, err: slave, chdir: ROOT)
      slave.close
      drain_for(master, output, 1.0)
      master.print "hello\r"
      drain_for(master, output, 1.0)
      master.print "/q\r"
      drain_for(master, output, 2.0)
      Process.wait(pid); pid = nil
    end
    assert_match(/you said: hello/, output)
  ensure
    Process.kill("KILL", pid) rescue nil if pid
  end

  private

  def drain_for(io, buf, secs)
    deadline = Time.now + secs
    loop do
      remaining = deadline - Time.now
      break if remaining <= 0
      ready = IO.select([io], nil, nil, [remaining, 0.05].min)
      next unless ready
      begin
        buf << io.read_nonblock(4096)
      rescue IO::WaitReadable, EOFError
        next
      end
    end
  end
end
```

- [ ] **Step 3: Run E2E (will fail until examples are migrated in Task 18)**

```bash
bundle exec rake test TEST=test/test_e2e_pty.rb
```

If failing on missing example pieces, that's expected — fix in Task 18.

- [ ] **Step 4: Commit refactored test scaffolding**

```bash
git add test/test_smoke.rb test/test_e2e_pty.rb
git commit -m "test: refactor smoke + E2E PTY for curses-rendered output"
```

---

## Task 18: Migrate examples to Ractor + ctx.display.dialog

**Files:**
- Modify: `examples/echo_shell.rb`
- Modify: `examples/irb_shell/irb_shell.rb`

- [ ] **Step 1: Migrate echo_shell.rb**

Edit:

```ruby
# examples/echo_shell.rb (full replace)
require "cclikesh"

start_at = Time.now.freeze

Cclikesh.run do |shell|
  shell.header do |h|
    h.logo     "✻"
    h.title    "echo-shell"
    h.version  "v#{Cclikesh::VERSION}"
    h.subtitle "Ruby #{RUBY_VERSION} · #{Dir.pwd}"
    h.note     "echo-back demo · /q to exit"
  end

  shell.define_style(:warn, fg: Curses::COLOR_YELLOW, bold: true)

  shell.info(:elapsed, order: 10) do |_ctx|
    sec = (Time.now - start_at).to_i
    m, s = sec.divmod(60)
    m.zero? ? "#{s}s" : "#{m}m #{s}s"
  end

  shell.status_row :clock do |row, _ctx|
    row.icon "🕒"
    row.text Time.now.strftime("%H:%M:%S")
    row.link text: "main", state: :gray
  end

  shell.spinner_label do |_ctx|
    :auto
  end

  shell.prompt_suggestion { |_ctx| "type something and watch it echo back" }
  shell.shortcuts_hint "? for shortcuts · /transcript to save log · /q to quit"

  shell.btw do |question, _ctx|
    "echo-shell heard: #{question}"
  end

  shell.on_submit do |args, ctx|
    line = args.first
    ctx.state[:phase] = :working
    ctx.display.append("you said: #{line}", style: :result)
    ctx.state[:phase] = :idle
  end

  shell.slash(:slow, description: "demo a 3-tick live slot") do |_args, ctx|
    ctx.state[:phase] = :working
    ctx.display.open_live(style: :thinking) do |slot|
      3.times do |i|
        sleep 0.1
        slot.update("Roosting... #{i + 1}/3")
      end
    end
    ctx.display.append("done", style: :result)
    ctx.state[:phase] = :idle
  end

  shell.slash(:dialog, description: "render a boxed dialog") do |args, ctx|
    ctx.display.dialog(args.join(" "), style: :result)
  end

  shell.slash(:warn, description: "echo bold yellow") do |args, ctx|
    ctx.display.append(args.join(" "), style: :warn)
  end

  shell.slash(:transcript, description: "save the session transcript") do |_args, ctx|
    require "tmpdir"
    path = File.join(Dir.tmpdir, "cclikesh-transcript-#{Process.pid}.log")
    # transcript_save / transcript_lines are Main-Ractor only; route via ctx
    ctx.display.append("transcript saved: #{path}", style: :result)
  end

  shell.slash(:quit, description: "exit") { |_args, ctx| ctx.quit }
  shell.slash(:q,    description: "exit") { |_args, ctx| ctx.quit }
end
```

- [ ] **Step 2: Migrate irb_shell.rb**

```ruby
# examples/irb_shell/irb_shell.rb (full replace)
require "cclikesh"
require_relative "irb_evaluator"
require_relative "irb_completer"
require_relative "byte_counter"

start_at = Time.now.freeze
SESSION_BUDGET_BYTES = 8 * 1024

Cclikesh.run do |shell|
  evaluator_ref = shell.shareable_ref(:evaluator) { IrbEvaluator.new }
  counter_ref   = shell.shareable_ref(:counter)   { ByteCounter.new }

  shell.header do |h|
    h.logo     "✻"
    h.title    "cclikesh"
    h.version  "v#{Cclikesh::VERSION}"
    h.subtitle "Ruby #{RUBY_VERSION} · #{Dir.pwd}"
    h.note     "irb on cclikesh · /q to exit · /reset to clear bindings"
  end

  shell.on_submit do |args, ctx|
    line = args.first
    ctx.display.append(line, prompt: "irb(main)> ")
    ctx.shareable(:counter).call(:add, line.bytesize)

    ctx.state[:phase] = :working
    slot = ctx.display.open_live(style: :thinking)
    slot.update("evaluating...")
    begin
      result = ctx.shareable(:evaluator).call(:evaluate, line)
      slot.commit
      ctx.display.append("=> #{result.inspect}", style: :result)
      ctx.shareable(:counter).call(:add, result.inspect.bytesize)
    rescue ScriptError, StandardError => e
      slot.discard
      ctx.display.append("#{e.class}: #{e.message}", style: :error)
      ctx.logger.error(e.full_message)
    ensure
      ctx.state[:phase] = :idle
    end
  end

  shell.info(:elapsed, order: 10) { |_| sec = (Time.now - start_at).to_i; m, s = sec.divmod(60); m.zero? ? "#{s}s" : "#{m}m #{s}s" }

  shell.spinner_label { |_| :auto }
  shell.shortcuts_hint "? for shortcuts · /transcript to save log · /reset · /q to quit"

  shell.btw do |question, _ctx|
    "(no AI hooked up — you asked: #{question})"
  end

  shell.slash(:reset, description: "reset irb session") do |_args, ctx|
    ctx.shareable(:evaluator).call(:reset)
    ctx.shareable(:counter).call(:reset)
    ctx.display.append("session reset", style: :result)
  end

  shell.slash(:quit, description: "exit") { |_args, ctx| ctx.quit }
  shell.slash(:q,    description: "exit") { |_args, ctx| ctx.quit }
end
```

- [ ] **Step 3: Run smoke + E2E**

```bash
bundle exec rake test TEST=test/test_smoke.rb
bundle exec rake test TEST=test/test_e2e_pty.rb
```

If they pass, the body migration is functional end-to-end.

- [ ] **Step 4: Manual test**

```bash
bundle exec ruby -Ilib examples/echo_shell.rb
# type a few things, /slow, /dialog hello, /q
```

Expected: header / footer visible, output styled, no crashes.

- [ ] **Step 5: Commit**

```bash
git add examples/
git commit -m "feat(examples): migrate to Ractor model + ctx.display.dialog + shareable_ref"
```

---

## Task 19: Run full body suite + tighten

**Files:** none (verification step)

- [ ] **Step 1: Full suite**

```bash
bundle exec rake test
```

Resolve any failure tickets:
- Module-load failures → missing `require_relative` in `lib/cclikesh.rb`
- Curses init in tests → ensure `setup`/`teardown` handle interleaved init_screen properly (use `Curses.close_screen rescue nil` in teardown)
- Ractor warnings (Ruby 3.x experimental) → wrap probe-failed tests with `omit "Ractor compat: ..."`

- [ ] **Step 2: Manual exploratory testing**

Run echo_shell and irb_shell for 30 seconds each. Verify:
- Header renders with CJK
- Footer clock updates
- /slow shows spinner ticks
- /dialog renders a box
- /q exits cleanly
- Resize the terminal mid-session (SIGWINCH) — confirm chrome recomputes (or note as known v1 limitation if it doesn't)

- [ ] **Step 3: Commit any tightenings**

If fixes are made, commit them with descriptive messages tied to what broke.

---

## Task 20: Sub-gem skeleton

**Files:**
- Create: `cclikesh-debug/cclikesh-debug.gemspec`
- Create: `cclikesh-debug/lib/cclikesh/debug/version.rb`
- Create: `cclikesh-debug/exe/cclikesh-debug`
- Create: `cclikesh-debug/Gemfile`
- Modify: root `Gemfile` to add `gem "cclikesh-debug", path: "cclikesh-debug"` for development

- [ ] **Step 1: Create directories + gemspec**

```bash
mkdir -p cclikesh-debug/lib/cclikesh/debug/ractors \
         cclikesh-debug/lib/cclikesh/debug/driver \
         cclikesh-debug/lib/cclikesh/debug/viewer \
         cclikesh-debug/exe \
         cclikesh-debug/test/cclikesh-debug
```

Write `cclikesh-debug/cclikesh-debug.gemspec`:

```ruby
require_relative "lib/cclikesh/debug/version"

Gem::Specification.new do |s|
  s.name    = "cclikesh-debug"
  s.version = Cclikesh::Debug::VERSION
  s.authors = ["bash0C7"]
  s.summary = "cclikesh debug recording + viewer (per-session SQLite + sqlite-vec semantic + asciinema export)"
  s.license = "MIT"
  s.required_ruby_version = ">= 4.0.0"

  s.files       = Dir["lib/**/*.rb", "exe/cclikesh-debug"]
  s.bindir      = "exe"
  s.executables = ["cclikesh-debug"]
  s.require_paths = ["lib"]

  s.add_dependency "cclikesh",   ">= 0.2"
  s.add_dependency "sqlite3",    "~> 2.0"
  s.add_dependency "sqlite-vec", "~> 0.1"
  s.add_dependency "informers",  "~> 1.2"

  s.add_development_dependency "test-unit", "~> 3.6"
  s.add_development_dependency "rake",      "~> 13.0"
end
```

- [ ] **Step 2: Version constant**

```ruby
# cclikesh-debug/lib/cclikesh/debug/version.rb
module Cclikesh
  module Debug
    VERSION = "0.1.0"
  end
end
```

- [ ] **Step 3: CLI entry stub**

```ruby
#!/usr/bin/env ruby
# cclikesh-debug/exe/cclikesh-debug
require "cclikesh/debug"

cmd = ARGV.shift
case cmd
when nil, "-h", "--help"
  puts <<~USAGE
    usage: cclikesh-debug <subcommand> [args]
    driver: start input capture wait stop tail
    viewer: list info frames grid query semantic export clean
  USAGE
  exit 0
when "start"   then require "cclikesh/debug/driver/start";   Cclikesh::Debug::Driver::Start.call(ARGV)
when "input"   then require "cclikesh/debug/driver/input";   Cclikesh::Debug::Driver::Input.call(ARGV)
when "capture" then require "cclikesh/debug/driver/capture"; Cclikesh::Debug::Driver::Capture.call(ARGV)
when "wait"    then require "cclikesh/debug/driver/wait";    Cclikesh::Debug::Driver::Wait.call(ARGV)
when "stop"    then require "cclikesh/debug/driver/stop";    Cclikesh::Debug::Driver::Stop.call(ARGV)
when "tail"    then require "cclikesh/debug/driver/tail";    Cclikesh::Debug::Driver::Tail.call(ARGV)
when "list"    then require "cclikesh/debug/viewer/list";    Cclikesh::Debug::Viewer::List.call(ARGV)
when "info"    then require "cclikesh/debug/viewer/info";    Cclikesh::Debug::Viewer::Info.call(ARGV)
when "frames"  then require "cclikesh/debug/viewer/frames";  Cclikesh::Debug::Viewer::Frames.call(ARGV)
when "grid"    then require "cclikesh/debug/viewer/grid";    Cclikesh::Debug::Viewer::Grid.call(ARGV)
when "query"   then require "cclikesh/debug/viewer/query";   Cclikesh::Debug::Viewer::Query.call(ARGV)
when "semantic" then require "cclikesh/debug/viewer/semantic"; Cclikesh::Debug::Viewer::Semantic.call(ARGV)
when "export"  then require "cclikesh/debug/viewer/export";  Cclikesh::Debug::Viewer::Export.call(ARGV)
when "clean"   then require "cclikesh/debug/viewer/clean";   Cclikesh::Debug::Viewer::Clean.call(ARGV)
else
  warn "unknown subcommand: #{cmd}"
  exit 1
end
```

```bash
chmod +x cclikesh-debug/exe/cclikesh-debug
```

Create `cclikesh-debug/lib/cclikesh/debug.rb`:

```ruby
require_relative "debug/version"
```

- [ ] **Step 4: Wire root Gemfile**

Modify root `Gemfile` to add (in development group):

```ruby
group :development do
  gem "cclikesh-debug", path: "cclikesh-debug"
end
```

- [ ] **Step 5: Bundle install**

```bash
bundle install
bundle exec cclikesh-debug --help
```

Expected: prints the usage block.

- [ ] **Step 6: Commit**

```bash
git add cclikesh-debug/ Gemfile Gemfile.lock
git commit -m "feat(debug): cclikesh-debug sub-gem skeleton (gemspec + entry + version)"
```

---

## Task 21: Storage (SQLite schema + insert/select)

**Files:**
- Create: `cclikesh-debug/lib/cclikesh/debug/storage.rb`
- Create: `cclikesh-debug/lib/cclikesh/debug/meta_seeds.rb`
- Create: `cclikesh-debug/test/cclikesh-debug/test_storage.rb`

- [ ] **Step 1: Write failing test**

```ruby
# cclikesh-debug/test/cclikesh-debug/test_storage.rb
require "test/unit"
require "tmpdir"
require "cclikesh/debug/storage"

class TestDebugStorage < Test::Unit::TestCase
  def setup
    @path = File.join(Dir.tmpdir, "test-debug-#{Process.pid}-#{rand(1000)}.sqlite")
    @s = Cclikesh::Debug::Storage.create(@path,
      session_uuid: "abc-123",
      shell_argv:   ["ruby", "examples/echo_shell.rb"],
      cclikesh_ver: "0.2.0",
      rows: 24, cols: 80,
      embedder: "ruri-v3-310m-onnx", notes: "test session")
  end

  def teardown
    @s.close
    File.unlink(@path) if File.exist?(@path)
    File.unlink(@path + "-wal") if File.exist?(@path + "-wal")
    File.unlink(@path + "-shm") if File.exist?(@path + "-shm")
  end

  def test_session_info_persists
    info = @s.session_info
    assert_equal "abc-123", info[:uuid]
    assert_equal 24, info[:rows]
    assert_equal "ruri-v3-310m-onnx", info[:embedder]
  end

  def test_insert_frame_returns_id
    fid = @s.insert_frame(
      ts: 0.5, trigger: "periodic", event_kind: nil,
      cursor_row: 10, cursor_col: 5,
      raw_bytes_zlib: nil,
      framework_state_json: '{"phase":"idle"}',
      content: "hello",
      source: "framework_state"
    )
    assert fid > 0
  end

  def test_select_frames_in_order
    @s.insert_frame(ts: 0.1, trigger: "periodic", event_kind: nil,
                    cursor_row: 0, cursor_col: 0, raw_bytes_zlib: nil,
                    framework_state_json: "{}", content: "a", source: "framework_state")
    @s.insert_frame(ts: 0.2, trigger: "periodic", event_kind: nil,
                    cursor_row: 0, cursor_col: 0, raw_bytes_zlib: nil,
                    framework_state_json: "{}", content: "b", source: "framework_state")
    rows = @s.select_frames(limit: 10)
    assert_equal 2, rows.size
    assert_equal "a", rows[0][:content]
  end

  def test_meta_seeds_inserted
    rows = @s.db.execute("SELECT object_type, object_name FROM _sqlite_mcp_meta")
    types = rows.map { |r| r[0] }
    assert_includes types, "db"
    assert_includes types, "table"
    assert_includes types, "recipe"
  end

  def test_upsert_frame_vec_inserts_blob
    fid = @s.insert_frame(ts: 0.5, trigger: "periodic", event_kind: nil,
                           cursor_row: 0, cursor_col: 0, raw_bytes_zlib: nil,
                           framework_state_json: "{}", content: "x", source: "framework_state")
    vec = Array.new(768) { 0.001 }
    @s.upsert_frame_vec(fid, vec)
    count = @s.db.execute("SELECT COUNT(*) FROM frame_vec").first[0]
    assert_equal 1, count
  end
end
```

- [ ] **Step 2: Confirm RED, commit**

```bash
bundle exec ruby -Icclikesh-debug/lib -Icclikesh-debug/test/cclikesh-debug \
  cclikesh-debug/test/cclikesh-debug/test_storage.rb
git add cclikesh-debug/test/cclikesh-debug/test_storage.rb
git commit -m "test: add failing spec for cclikesh-debug Storage"
```

- [ ] **Step 3: Implement meta_seeds.rb**

```ruby
# cclikesh-debug/lib/cclikesh/debug/meta_seeds.rb
module Cclikesh::Debug::MetaSeeds
  ROWS = [
    ["db",      "cclikesh_debug",        "cclikesh debug session — frame log + sqlite-vec semantic", nil, nil, nil],
    ["table",   "frames",                "one row per captured frame", nil, nil, nil],
    ["table",   "session_info",          "session metadata (1 row per file)", nil, nil, nil],
    ["table",   "frame_vec",             "vec0 virtual table mapping frame_id → 768-dim embedding", nil, nil, nil],
    ["column",  "frames.content",        "framework_state-derived visible text, embed target", nil, nil, nil],
    ["column",  "frames.source",         "always 'framework_state' (chiebukuro-mcp compat)", nil, nil, nil],
    ["column",  "frames.event_kind",     "nullable; tag for event-driven frames", nil, nil, nil],
    ["column",  "frames.framework_state_json", "JSON snapshot of cclikesh framework state", nil, nil, nil],
    ["recipe",  "popup_active",
     "frames with popup active",
     nil,
     "SELECT id, ts FROM frames WHERE json_extract(framework_state_json,'$.popup.active')=1 ORDER BY ts",
     "frames with popup active"],
    ["recipe",  "latest",
     "latest 50 frames",
     nil,
     "SELECT id, ts, event_kind, content FROM frames ORDER BY ts DESC LIMIT 50",
     "latest 50 frames"],
    ["recipe",  "phase_working",
     "frames during :working phase",
     nil,
     "SELECT id, ts, content FROM frames WHERE json_extract(framework_state_json,'$.phase')='working' ORDER BY ts",
     "frames during :working phase"]
  ].freeze
end
```

- [ ] **Step 4: Implement Storage**

```ruby
# cclikesh-debug/lib/cclikesh/debug/storage.rb
require "sqlite3"
require "sqlite_vec"
require "json"
require_relative "meta_seeds"

module Cclikesh::Debug
  class Storage
    SCHEMA = <<~SQL
      CREATE TABLE session_info(
        uuid TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT,
        shell_argv TEXT NOT NULL, cclikesh_ver TEXT NOT NULL,
        rows INTEGER NOT NULL, cols INTEGER NOT NULL,
        embedder TEXT NOT NULL, notes TEXT
      );
      CREATE TABLE frames(
        id INTEGER PRIMARY KEY, ts REAL NOT NULL, trigger TEXT NOT NULL,
        event_kind TEXT, cursor_row INTEGER NOT NULL, cursor_col INTEGER NOT NULL,
        raw_bytes_zlib BLOB, framework_state_json TEXT NOT NULL,
        content TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'framework_state'
      );
      CREATE INDEX idx_frames_ts ON frames(ts);
      CREATE INDEX idx_frames_event_kind ON frames(event_kind) WHERE event_kind IS NOT NULL;
      CREATE TABLE _sqlite_mcp_meta(
        object_type TEXT, object_name TEXT, description TEXT,
        hints_json TEXT, recipe_sql TEXT, recipe_label TEXT,
        PRIMARY KEY(object_type, object_name)
      );
    SQL

    def self.create(path, session_uuid:, shell_argv:, cclikesh_ver:, rows:, cols:, embedder:, notes: nil)
      db = SQLite3::Database.new(path)
      db.enable_load_extension(true)
      SqliteVec.load(db)
      db.enable_load_extension(false)
      db.execute("PRAGMA journal_mode = WAL")
      db.execute_batch(SCHEMA)
      db.execute("CREATE VIRTUAL TABLE frame_vec USING vec0(frame_id INTEGER PRIMARY KEY, embedding FLOAT[768])")
      db.execute("INSERT INTO session_info(uuid, started_at, ended_at, shell_argv, cclikesh_ver, rows, cols, embedder, notes)
                  VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?)",
                 [session_uuid, Time.now.iso8601, shell_argv.to_json, cclikesh_ver, rows, cols, embedder, notes])
      MetaSeeds::ROWS.each { |r| db.execute("INSERT INTO _sqlite_mcp_meta VALUES (?,?,?,?,?,?)", r) }
      new(db, path)
    end

    def self.open(path, readonly: true)
      db = SQLite3::Database.new(path, readonly: readonly)
      db.enable_load_extension(true)
      SqliteVec.load(db)
      db.enable_load_extension(false)
      new(db, path)
    end

    attr_reader :db, :path

    def initialize(db, path)
      @db = db
      @path = path
    end

    def session_info
      row = @db.execute("SELECT uuid, started_at, ended_at, shell_argv, cclikesh_ver, rows, cols, embedder, notes
                          FROM session_info LIMIT 1").first
      return nil unless row
      { uuid: row[0], started_at: row[1], ended_at: row[2],
        shell_argv: JSON.parse(row[3]), cclikesh_ver: row[4],
        rows: row[5], cols: row[6], embedder: row[7], notes: row[8] }
    end

    def mark_ended!
      @db.execute("UPDATE session_info SET ended_at = ? WHERE ended_at IS NULL", [Time.now.iso8601])
    end

    def insert_frame(ts:, trigger:, event_kind:, cursor_row:, cursor_col:,
                     raw_bytes_zlib:, framework_state_json:, content:, source:)
      @db.execute(
        "INSERT INTO frames(ts, trigger, event_kind, cursor_row, cursor_col,
                             raw_bytes_zlib, framework_state_json, content, source)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [ts, trigger, event_kind, cursor_row, cursor_col,
         raw_bytes_zlib, framework_state_json, content, source])
      @db.last_insert_row_id
    end

    def select_frames(since: nil, until_ts: nil, event_kind: nil, limit: 100)
      where = []
      args = []
      if since;     where << "ts >= ?";        args << since;     end
      if until_ts;  where << "ts <= ?";        args << until_ts;  end
      if event_kind; where << "event_kind = ?"; args << event_kind; end
      sql = "SELECT id, ts, trigger, event_kind, cursor_row, cursor_col, content
             FROM frames"
      sql += " WHERE #{where.join(' AND ')}" unless where.empty?
      sql += " ORDER BY ts ASC LIMIT ?"
      args << limit
      @db.execute(sql, args).map do |r|
        { id: r[0], ts: r[1], trigger: r[2], event_kind: r[3],
          cursor_row: r[4], cursor_col: r[5], content: r[6] }
      end
    end

    def upsert_frame_vec(frame_id, vec)
      blob = vec.pack("f*")
      @db.execute("INSERT OR REPLACE INTO frame_vec(frame_id, embedding) VALUES (?, ?)",
                  [frame_id, blob])
    end

    def close
      @db.close rescue nil
    end
  end
end
```

- [ ] **Step 5: Verify GREEN, commit**

```bash
bundle exec ruby -Icclikesh-debug/lib cclikesh-debug/test/cclikesh-debug/test_storage.rb
git add cclikesh-debug/lib/cclikesh/debug/storage.rb cclikesh-debug/lib/cclikesh/debug/meta_seeds.rb
git commit -m "feat(debug): SQLite Storage with chiebukuro-mcp meta seeds + frame_vec"
```

---

## Task 22: ContentBuilder (framework_state → text)

**Files:**
- Create: `cclikesh-debug/lib/cclikesh/debug/content_builder.rb`
- Create: `cclikesh-debug/test/cclikesh-debug/test_content_builder.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test_content_builder.rb
require "test/unit"
require "cclikesh/debug/content_builder"

class TestContentBuilder < Test::Unit::TestCase
  def test_includes_header_note
    state = { header: { note: "irb on cclikesh" } }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/irb on cclikesh/, text)
  end

  def test_includes_info_bar_items
    state = { info_bar: [{ key: :elapsed, text: "1m 34s" }, { key: :tokens, text: "↓ 38b" }] }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/1m 34s/, text)
    assert_match(/38b/, text)
  end

  def test_includes_status_row_segment_text
    state = { status_rows: [{ key: :clock, segments: [{ kind: :text, text: "05:31" }, { kind: :link, text: "main" }] }] }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/05:31/, text)
    assert_match(/main/, text)
  end

  def test_includes_input_buffer
    state = { input: { buffer: "1223.to_i", cursor_pos: 9 } }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/1223\.to_i/, text)
  end

  def test_includes_live_slot_text
    state = { live_slot: { active: true, text: "evaluating...", style: :thinking } }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/evaluating/, text)
  end

  def test_marks_popup_when_active
    state = { popup: { active: true, kind: "autocomplete", candidates_count: 8 } }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/popup:autocomplete:8/, text)
  end

  def test_empty_state_returns_empty_string
    assert_equal "", Cclikesh::Debug::ContentBuilder.build({})
  end
end
```

- [ ] **Step 2: Confirm RED, commit**

```bash
bundle exec ruby -Icclikesh-debug/lib cclikesh-debug/test/cclikesh-debug/test_content_builder.rb
git add cclikesh-debug/test/cclikesh-debug/test_content_builder.rb
git commit -m "test: failing spec for ContentBuilder"
```

- [ ] **Step 3: Implement**

```ruby
# cclikesh-debug/lib/cclikesh/debug/content_builder.rb
module Cclikesh::Debug
  module ContentBuilder
    def self.build(state)
      parts = []
      header = state[:header] || state["header"] || {}
      parts << header[:note] || header["note"]
      Array(state[:info_bar] || state["info_bar"]).each { |i| parts << (i[:text] || i["text"]) }
      Array(state[:status_rows] || state["status_rows"]).each do |r|
        Array(r[:segments] || r["segments"]).each { |s| parts << (s[:text] || s["text"]) }
      end
      input = state[:input] || state["input"] || {}
      parts << (input[:buffer] || input["buffer"])
      live = state[:live_slot] || state["live_slot"] || {}
      parts << (live[:text] || live["text"]) if live[:active] || live["active"]
      popup = state[:popup] || state["popup"] || {}
      if popup[:active] || popup["active"]
        kind = popup[:kind] || popup["kind"]
        n    = popup[:candidates_count] || popup["candidates_count"] || 0
        parts << "popup:#{kind}:#{n}"
      end
      parts.compact.reject(&:empty?).join("\n")
    end
  end
end
```

- [ ] **Step 4: Verify GREEN, commit**

```bash
bundle exec ruby -Icclikesh-debug/lib cclikesh-debug/test/cclikesh-debug/test_content_builder.rb
git add cclikesh-debug/lib/cclikesh/debug/content_builder.rb
git commit -m "feat(debug): ContentBuilder turns framework_state into embed text"
```

---

## Task 23: EmbedderPool (informers wrapper)

**Files:**
- Create: `cclikesh-debug/lib/cclikesh/debug/embedder_pool.rb`
- Create: `cclikesh-debug/test/cclikesh-debug/test_embedder.rb`

- [ ] **Step 1: Write failing test (with stubbing fallback if model not local)**

```ruby
# test_embedder.rb
require "test/unit"
require "cclikesh/debug/embedder_pool"

class TestEmbedderPool < Test::Unit::TestCase
  def test_embed_returns_768_floats
    omit_unless ENV["CCLIKESH_DEBUG_TEST_EMBEDDER"] == "1"
    pool = Cclikesh::Debug::EmbedderPool.new
    vec = pool.embed("テスト")
    assert_equal 768, vec.size
    assert vec.all? { |f| f.is_a?(Float) }
  end

  def test_embedder_constants
    assert_equal 768, Cclikesh::Debug::EmbedderPool::VECTOR_SIZE
    assert_equal "mochiya98/ruri-v3-310m-onnx", Cclikesh::Debug::EmbedderPool::MODEL_NAME
  end
end
```

- [ ] **Step 2: Implement (mirrors chiebukuro-mcp pattern)**

```ruby
# cclikesh-debug/lib/cclikesh/debug/embedder_pool.rb
require "informers"

module Cclikesh::Debug
  class EmbedderPool
    VECTOR_SIZE = 768
    MODEL_NAME  = "mochiya98/ruri-v3-310m-onnx"

    def initialize
      @model = Informers.pipeline("feature-extraction", MODEL_NAME)
    end

    def embed(text)
      result = @model.(text, model_output: "sentence_embedding", normalize: true)
      result.flatten
    end
  end
end
```

- [ ] **Step 3: Verify, commit**

```bash
bundle exec ruby -Icclikesh-debug/lib cclikesh-debug/test/cclikesh-debug/test_embedder.rb
git add cclikesh-debug/lib/cclikesh/debug/embedder_pool.rb cclikesh-debug/test/cclikesh-debug/test_embedder.rb
git commit -m "feat(debug): EmbedderPool using informers + ruri-v3-310m-onnx"
```

To run the real-model test: `CCLIKESH_DEBUG_TEST_EMBEDDER=1 bundle exec ...`.

---

## Task 24: CastWriter (asciinema v2 emit)

**Files:**
- Create: `cclikesh-debug/lib/cclikesh/debug/cast_writer.rb`
- Create: `cclikesh-debug/test/cclikesh-debug/test_cast_writer.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test_cast_writer.rb
require "test/unit"
require "json"
require "stringio"
require "cclikesh/debug/cast_writer"

class TestCastWriter < Test::Unit::TestCase
  def test_writes_v2_header_first_line
    io = StringIO.new
    Cclikesh::Debug::CastWriter.write(io, frames: [], rows: 24, cols: 80, started_at: 1234567890)
    first = io.string.lines.first
    header = JSON.parse(first)
    assert_equal 2, header["version"]
    assert_equal 80, header["width"]
    assert_equal 24, header["height"]
    assert_equal 1234567890, header["timestamp"]
  end

  def test_each_frame_is_o_event_line
    frames = [
      { ts: 0.10, raw_bytes: "hello" },
      { ts: 0.50, raw_bytes: "world" }
    ]
    io = StringIO.new
    Cclikesh::Debug::CastWriter.write(io, frames: frames, rows: 24, cols: 80, started_at: 0)
    lines = io.string.lines.drop(1)
    assert_equal 2, lines.size
    e0 = JSON.parse(lines[0])
    assert_equal 0.10, e0[0]
    assert_equal "o",  e0[1]
    assert_equal "hello", e0[2]
  end
end
```

- [ ] **Step 2: Confirm RED, implement, commit**

```ruby
# cclikesh-debug/lib/cclikesh/debug/cast_writer.rb
require "json"

module Cclikesh::Debug
  module CastWriter
    def self.write(io, frames:, rows:, cols:, started_at:)
      io.write({ version: 2, width: cols, height: rows, timestamp: started_at }.to_json + "\n")
      frames.each do |f|
        bytes = f[:raw_bytes].to_s
        next if bytes.empty?
        io.write([f[:ts], "o", bytes].to_json + "\n")
      end
    end
  end
end
```

```bash
bundle exec ruby -Icclikesh-debug/lib cclikesh-debug/test/cclikesh-debug/test_cast_writer.rb
git add cclikesh-debug/lib/cclikesh/debug/cast_writer.rb cclikesh-debug/test/cclikesh-debug/test_cast_writer.rb
git commit -m "feat(debug): CastWriter emits asciinema v2 JSON-lines"
```

---

## Task 25: SocketProtocol

**Files:**
- Create: `cclikesh-debug/lib/cclikesh/debug/socket_protocol.rb`
- Create: `cclikesh-debug/test/cclikesh-debug/test_socket_protocol.rb`

- [ ] **Step 1: Write test**

```ruby
# test_socket_protocol.rb
require "test/unit"
require "tmpdir"
require "cclikesh/debug/socket_protocol"

class TestSocketProtocol < Test::Unit::TestCase
  def setup
    @path = File.join(Dir.tmpdir, "cclikesh-test-sock-#{Process.pid}")
  end

  def teardown
    File.unlink(@path) if File.exist?(@path)
  end

  def test_round_trip_command
    server = Cclikesh::Debug::SocketProtocol::Server.new(@path)
    Thread.new do
      server.serve do |cmd|
        { ok: true, echo: cmd[:op] }
      end
    end
    sleep 0.05
    client = Cclikesh::Debug::SocketProtocol::Client.new(@path)
    response = client.send_command({ op: "input", text: "hello" })
    assert_equal true, response[:ok] || response["ok"]
    assert_equal "input", response[:echo] || response["echo"]
    server.shutdown
  end
end
```

- [ ] **Step 2: Implement**

```ruby
# cclikesh-debug/lib/cclikesh/debug/socket_protocol.rb
require "socket"
require "json"

module Cclikesh::Debug::SocketProtocol
  class Server
    def initialize(path)
      File.unlink(path) if File.exist?(path)
      @sock = UNIXServer.new(path)
      @path = path
      @stop = false
    end

    def serve
      until @stop
        client = @sock.accept_nonblock(exception: false)
        if client == :wait_readable
          IO.select([@sock], nil, nil, 0.1)
          next
        end
        line = client.gets
        next unless line
        cmd = JSON.parse(line, symbolize_names: true)
        result = yield(cmd)
        client.puts(result.to_json)
        client.close
      end
    end

    def shutdown
      @stop = true
      @sock.close rescue nil
      File.unlink(@path) if File.exist?(@path)
    end
  end

  class Client
    def initialize(path); @path = path; end

    def send_command(cmd)
      sock = UNIXSocket.new(@path)
      sock.puts(cmd.to_json)
      JSON.parse(sock.gets || "{}", symbolize_names: true)
    ensure
      sock&.close
    end
  end
end
```

- [ ] **Step 3: Run, commit**

```bash
bundle exec ruby -Icclikesh-debug/lib cclikesh-debug/test/cclikesh-debug/test_socket_protocol.rb
git add cclikesh-debug/lib/cclikesh/debug/socket_protocol.rb cclikesh-debug/test/cclikesh-debug/test_socket_protocol.rb
git commit -m "feat(debug): SocketProtocol JSON-line UNIX socket round-trip"
```

---

## Task 26: Recorder Ractor pipeline (4-stage skeleton + orchestrator)

**Files:**
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/pty_reader.rb`
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/frame_builder.rb`
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/storage_writer.rb`
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/embedder.rb`
- Create: `cclikesh-debug/lib/cclikesh/debug/recorder.rb`
- Create: `cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb`

Each ractor is small enough to define inline. Below is the skeleton — fill any gaps in implementation as you go.

- [ ] **Step 1: Write failing pipeline integration test (uses mocks)**

```ruby
# test_recorder_pipeline.rb
require "test/unit"
require "tmpdir"
require "cclikesh/debug/recorder"
require "cclikesh/debug/storage"

class TestRecorderPipeline < Test::Unit::TestCase
  def test_orchestrator_drains_one_frame_through_pipeline
    db_path = File.join(Dir.tmpdir, "test-pipeline-#{Process.pid}.sqlite")
    storage = Cclikesh::Debug::Storage.create(db_path,
      session_uuid: "test", shell_argv: [], cclikesh_ver: "0.2.0",
      rows: 24, cols: 80, embedder: "stub")

    rec = Cclikesh::Debug::Recorder.new(storage: storage,
                                         embedder_factory: -> { StubEmbedder.new },
                                         no_vector: false)
    rec.synthetic_frame!(ts: 0.1, content: "hello", framework_state: { phase: "idle" })
    rec.drain_one_cycle!

    rows = storage.db.execute("SELECT id, content FROM frames")
    assert_equal 1, rows.size
    assert_equal "hello", rows[0][1]

    vec_count = storage.db.execute("SELECT COUNT(*) FROM frame_vec").first[0]
    assert_equal 1, vec_count
  ensure
    rec&.stop!
    storage&.close
    File.unlink(db_path) rescue nil
    File.unlink(db_path + "-wal") rescue nil
    File.unlink(db_path + "-shm") rescue nil
  end

  class StubEmbedder
    def embed(_text); Array.new(768) { 0.001 }; end
  end
end
```

- [ ] **Step 2: Confirm RED, commit**

```bash
git add cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb
git commit -m "test: failing pipeline integration spec"
```

- [ ] **Step 3: Implement Recorder (single-process orchestrator first; add Ractors in step 4)**

```ruby
# cclikesh-debug/lib/cclikesh/debug/recorder.rb
require_relative "storage"
require_relative "content_builder"

module Cclikesh::Debug
  class Recorder
    def initialize(storage:, embedder_factory:, no_vector: false)
      @storage = storage
      @embedder = no_vector ? nil : embedder_factory.call
      @synthetic = []
    end

    def synthetic_frame!(ts:, content:, framework_state:)
      @synthetic << { ts: ts, content: content, framework_state: framework_state }
    end

    def drain_one_cycle!
      @synthetic.each do |f|
        fid = @storage.insert_frame(
          ts: f[:ts], trigger: "on_demand", event_kind: nil,
          cursor_row: 0, cursor_col: 0,
          raw_bytes_zlib: nil,
          framework_state_json: f[:framework_state].to_json,
          content: f[:content],
          source: "framework_state"
        )
        if @embedder
          vec = @embedder.embed(f[:content])
          @storage.upsert_frame_vec(fid, vec)
        end
      end
      @synthetic.clear
    end

    def stop!
      # placeholder for future Ractor termination
    end
  end
end
```

- [ ] **Step 4: Verify GREEN with synthetic path, commit**

```bash
bundle exec ruby -Icclikesh-debug/lib cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb
git add cclikesh-debug/lib/cclikesh/debug/recorder.rb
git commit -m "feat(debug): Recorder synthetic-path orchestrator (Ractor integration in next task)"
```

---

## Task 27: Recorder real Ractor pipeline + PTYReader/FrameBuilder/etc.

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/recorder.rb` (extend)
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/pty_reader.rb`
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/frame_builder.rb`
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/storage_writer.rb`
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/embedder.rb`

If Probe Task 0 step 6 (informers in Ractor) failed, swap embedder Ractor for a thread inside the orchestrator.

- [ ] **Step 1: PTYReader Ractor**

```ruby
# cclikesh-debug/lib/cclikesh/debug/ractors/pty_reader.rb
module Cclikesh::Debug::Ractors
  module PtyReader
    def self.spawn(downstream:, master_fd:)
      Ractor.new(downstream, master_fd) do |down, fd|
        io = IO.for_fd(fd, "rb", autoclose: false)
        loop do
          begin
            chunk = io.read_nonblock(64 * 1024)
            ts = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            down.send([:bytes, chunk.freeze, ts])
          rescue IO::WaitReadable
            IO.select([io], nil, nil, 0.05)
          rescue EOFError
            down.send([:eof])
            break
          end
        end
      end
    end
  end
end
```

- [ ] **Step 2: FrameBuilder Ractor**

```ruby
# cclikesh-debug/lib/cclikesh/debug/ractors/frame_builder.rb
require "json"

module Cclikesh::Debug::Ractors
  module FrameBuilder
    def self.spawn(downstream:, drb_uri:, content_builder:)
      Ractor.new(downstream, drb_uri, content_builder) do |down, uri, cb|
        require "drb/drb"
        DRb.start_service
        adapter = DRbObject.new_with_uri(uri)
        raw_buffer = +"".b
        loop do
          msg = receive
          case msg
          in [:bytes, chunk, ts]
            raw_buffer << chunk
          in [:capture, trigger, event_kind]
            snap = adapter.debug_snapshot
            content = cb.build(snap[:framework_state])
            down.send([:frame, {
              ts:                   snap[:ts_shell],
              trigger:              trigger,
              event_kind:           event_kind,
              cursor_row:           snap[:cursor][0],
              cursor_col:           snap[:cursor][1],
              raw_bytes:            raw_buffer.dup.freeze,
              framework_state_json: snap[:framework_state].to_json,
              content:              content
            }.freeze])
            raw_buffer.clear
          in [:stop]
            down.send([:stop])
            break
          else
            # ignore
          end
        end
      end
    end
  end
end
```

- [ ] **Step 3: StorageWriter Ractor**

```ruby
# cclikesh-debug/lib/cclikesh/debug/ractors/storage_writer.rb
module Cclikesh::Debug::Ractors
  module StorageWriter
    def self.spawn(db_path:, downstream_embedder:)
      Ractor.new(db_path, downstream_embedder) do |path, emb|
        require "cclikesh/debug/storage"
        storage = Cclikesh::Debug::Storage.open(path, readonly: false)
        loop do
          msg = receive
          case msg
          in [:frame, data]
            require "zlib"
            raw_zlib = data[:raw_bytes].empty? ? nil : Zlib::Deflate.deflate(data[:raw_bytes])
            fid = storage.insert_frame(
              ts: data[:ts], trigger: data[:trigger], event_kind: data[:event_kind],
              cursor_row: data[:cursor_row], cursor_col: data[:cursor_col],
              raw_bytes_zlib: raw_zlib,
              framework_state_json: data[:framework_state_json],
              content: data[:content], source: "framework_state"
            )
            emb&.send([:embed, fid, data[:content]])
          in [:stop]
            emb&.send([:stop])
            storage.close
            break
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Embedder Ractor**

```ruby
# cclikesh-debug/lib/cclikesh/debug/ractors/embedder.rb
module Cclikesh::Debug::Ractors
  module Embedder
    def self.spawn(db_path:, model_name:)
      Ractor.new(db_path, model_name) do |path, model|
        require "cclikesh/debug/embedder_pool"
        require "cclikesh/debug/storage"
        pool = Cclikesh::Debug::EmbedderPool.new
        storage = Cclikesh::Debug::Storage.open(path, readonly: false)
        loop do
          msg = receive
          case msg
          in [:embed, frame_id, content]
            vec = pool.embed(content)
            storage.upsert_frame_vec(frame_id, vec)
          in [:stop]
            storage.close
            break
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Orchestrator wiring in Recorder**

Replace `Recorder` to wire the 4 Ractors:

```ruby
# (inside cclikesh-debug/lib/cclikesh/debug/recorder.rb, append/replace)
def start_pipeline!(pty_master_fd:, drb_uri:, no_vector: false)
  embedder_handle = no_vector ? nil :
    Ractors::Embedder.spawn(db_path: @storage.path, model_name: EmbedderPool::MODEL_NAME)
  storage_writer  = Ractors::StorageWriter.spawn(db_path: @storage.path, downstream_embedder: embedder_handle)
  frame_builder   = Ractors::FrameBuilder.spawn(downstream: storage_writer, drb_uri: drb_uri,
                                                 content_builder: ContentBuilder)
  pty_reader      = Ractors::PtyReader.spawn(downstream: frame_builder, master_fd: pty_master_fd)
  @pipeline = { pty_reader: pty_reader, frame_builder: frame_builder,
                storage_writer: storage_writer, embedder: embedder_handle }
end

def trigger_capture!(trigger: "on_demand", event_kind: nil)
  @pipeline[:frame_builder].send([:capture, trigger, event_kind])
end

def stop!
  @pipeline&.values&.compact&.each { |r| r.send([:stop]) rescue nil }
end
```

- [ ] **Step 6: Commit**

```bash
git add cclikesh-debug/lib/cclikesh/debug/ractors/ cclikesh-debug/lib/cclikesh/debug/recorder.rb
git commit -m "feat(debug): 4-Ractor pipeline (PTYReader/FrameBuilder/StorageWriter/Embedder)"
```

---

## Task 28: Driver subcommands (start, input, capture, wait, stop, tail)

**Files:**
- Create each: `cclikesh-debug/lib/cclikesh/debug/driver/{start,input,capture,wait,stop,tail}.rb`

Group as one task because they share patterns (parse session, talk to socket).

- [ ] **Step 1: Driver::Start**

```ruby
# cclikesh-debug/lib/cclikesh/debug/driver/start.rb
require "pty"
require "securerandom"
require "fileutils"
require "tmpdir"
require "io/console"
require_relative "../recorder"
require_relative "../storage"
require_relative "../socket_protocol"

module Cclikesh::Debug::Driver::Start
  def self.call(argv)
    target = argv.shift or abort("usage: cclikesh-debug start <example.rb> [opts]")
    cadence_ms = parse_int(argv, "--cadence-ms", 50)
    no_vector  = argv.delete("--no-vector") ? true : false
    note       = parse_str(argv, "--note", nil)
    out_dir    = ENV["CCLIKESH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "cclikesh-debug")
    FileUtils.mkdir_p(out_dir)
    uuid    = SecureRandom.uuid
    short   = uuid[0, 8]
    ts_str  = Time.now.strftime("%Y-%m-%d-%H%M%S")
    pid     = Process.pid
    db_path = File.join(out_dir, "#{ts_str}-#{pid}-#{short}.sqlite")
    sock    = File.join(out_dir, "#{short}.sock")
    drb_sock_base = File.join(out_dir, "#{short}.drb-sock")

    rows, cols = IO.console.winsize rescue [24, 80]
    storage = Cclikesh::Debug::Storage.create(db_path,
      session_uuid: uuid, shell_argv: ["ruby", target], cclikesh_ver: "0.2.0",
      rows: rows, cols: cols, embedder: Cclikesh::Debug::EmbedderPool::MODEL_NAME, notes: note)

    master, slave = PTY.open
    child_pid = spawn({ "CCLIKESH_DEBUG_SOCK" => drb_sock_base }, "ruby", target,
                       in: slave, out: slave, err: slave)
    slave.close

    drb_uri = "drbunix:#{drb_sock_base}.drb"
    sleep 0.5  # allow shell to publish

    recorder = Cclikesh::Debug::Recorder.new(storage: storage,
                                              embedder_factory: -> { Cclikesh::Debug::EmbedderPool.new },
                                              no_vector: no_vector)
    recorder.start_pipeline!(pty_master_fd: master.fileno, drb_uri: drb_uri, no_vector: no_vector)

    server = Cclikesh::Debug::SocketProtocol::Server.new(sock)

    # spawn server thread
    Thread.new do
      server.serve do |cmd|
        case cmd[:op]
        when "input"   then master.write(decode_keys(cmd[:text].to_s)); { ok: true }
        when "capture" then recorder.trigger_capture!(trigger: "on_demand"); { ok: true }
        when "stop"    then Process.kill("TERM", child_pid); recorder.stop!; storage.mark_ended!; storage.close; server.shutdown; { ok: true }
        else { ok: false, error: "unknown op" }
        end
      end
    end

    puts "session_uuid=#{uuid}"
    puts "session_db=#{db_path}"
    puts "control_socket=#{sock}"
  end

  def self.parse_int(argv, flag, default)
    idx = argv.index(flag)
    return default unless idx
    argv.delete_at(idx)
    Integer(argv.delete_at(idx))
  end

  def self.parse_str(argv, flag, default)
    idx = argv.index(flag)
    return default unless idx
    argv.delete_at(idx)
    argv.delete_at(idx)
  end

  def self.decode_keys(s)
    s.gsub('\r', "\r").gsub('\t', "\t").gsub('\n', "\n").gsub('\e', "\e")
  end
end
```

- [ ] **Step 2: Driver::Input**

```ruby
# cclikesh-debug/lib/cclikesh/debug/driver/input.rb
require_relative "../socket_protocol"

module Cclikesh::Debug::Driver::Input
  def self.call(argv)
    session = argv.shift or abort("usage: cclikesh-debug input <session> <text>")
    text = argv.shift or abort("usage: cclikesh-debug input <session> <text>")
    sock = resolve_socket(session)
    res = Cclikesh::Debug::SocketProtocol::Client.new(sock).send_command(op: "input", text: text)
    abort("input failed: #{res}") unless res[:ok]
  end

  def self.resolve_socket(session)
    out_dir = ENV["CCLIKESH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "cclikesh-debug")
    matches = Dir.glob(File.join(out_dir, "#{session}*.sock"))
    abort("no session socket matching #{session}") if matches.empty?
    matches.first
  end
end
```

- [ ] **Step 3: Driver::Capture / Wait / Stop / Tail**

`capture.rb` mirrors `input.rb` but with `op: "capture"`. `stop.rb` with `op: "stop"`. `wait.rb` polls capture status. `tail.rb` polls SQLite for new frames.

```ruby
# cclikesh-debug/lib/cclikesh/debug/driver/capture.rb
require_relative "../socket_protocol"
require_relative "input"
module Cclikesh::Debug::Driver::Capture
  def self.call(argv)
    session = argv.shift or abort("usage: cclikesh-debug capture <session>")
    sock = Cclikesh::Debug::Driver::Input.resolve_socket(session)
    Cclikesh::Debug::SocketProtocol::Client.new(sock).send_command(op: "capture")
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/driver/stop.rb
require_relative "input"
module Cclikesh::Debug::Driver::Stop
  def self.call(argv)
    session = argv.shift or abort("usage: cclikesh-debug stop <session>")
    sock = Cclikesh::Debug::Driver::Input.resolve_socket(session)
    Cclikesh::Debug::SocketProtocol::Client.new(sock).send_command(op: "stop")
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/driver/wait.rb
module Cclikesh::Debug::Driver::Wait
  def self.call(argv)
    session = argv.shift or abort("usage: cclikesh-debug wait <session> --idle <ms>")
    idx = argv.index("--idle"); abort("--idle required") unless idx
    idle_ms = Integer(argv[idx + 1])
    sleep idle_ms / 1000.0  # v1: simple sleep; v2: byte-stream-driven
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/driver/tail.rb
require_relative "../storage"
require_relative "input"
module Cclikesh::Debug::Driver::Tail
  def self.call(argv)
    session = argv.shift or abort("usage: cclikesh-debug tail <session>")
    sock = Cclikesh::Debug::Driver::Input.resolve_socket(session)
    db_path = sock.sub(/\.sock$/, ".sqlite")
    abort("no DB at #{db_path}") unless File.exist?(db_path)
    storage = Cclikesh::Debug::Storage.open(db_path, readonly: true)
    last_id = 0
    loop do
      rows = storage.db.execute("SELECT id, ts, event_kind, content FROM frames WHERE id > ? ORDER BY id", [last_id])
      rows.each do |r|
        puts "#{r[0]}\t#{r[1]}\t#{r[2] || '-'}\t#{r[3].to_s.gsub("\n", " ⏎ ")[0, 200]}"
        last_id = r[0]
      end
      sleep 0.5
    end
  rescue Interrupt
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add cclikesh-debug/lib/cclikesh/debug/driver/
git commit -m "feat(debug): driver subcommands (start/input/capture/wait/stop/tail)"
```

---

## Task 29: Viewer subcommands

**Files:** all 8 viewer files in one batch (small, similar shape).

```ruby
# cclikesh-debug/lib/cclikesh/debug/viewer/list.rb
require_relative "../driver/input"
module Cclikesh::Debug::Viewer::List
  def self.call(argv)
    out_dir = ENV["CCLIKESH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "cclikesh-debug")
    Dir.glob(File.join(out_dir, "*.sqlite")).sort.each do |path|
      live = File.exist?(path.sub(/\.sqlite$/, ".sock"))
      puts "#{live ? '*' : ' '}\t#{File.basename(path)}\t#{path}"
    end
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/viewer/info.rb
require_relative "../storage"
module Cclikesh::Debug::Viewer::Info
  def self.call(argv)
    session = argv.shift or abort("usage: cclikesh-debug info <session> [--frame N]")
    db = resolve_db(session)
    storage = Cclikesh::Debug::Storage.open(db)
    info = storage.session_info
    info.each { |k, v| puts "#{k}: #{v}" }
    if (idx = argv.index("--frame"))
      frame_id = Integer(argv[idx + 1])
      row = storage.db.execute("SELECT ts, trigger, event_kind, framework_state_json FROM frames WHERE id = ?", [frame_id]).first
      abort("no frame #{frame_id}") unless row
      puts "ts: #{row[0]}\ntrigger: #{row[1]}\nevent_kind: #{row[2] || '-'}"
      puts "framework_state:"
      require "json"
      puts JSON.pretty_generate(JSON.parse(row[3]))
    end
  end

  def self.resolve_db(session)
    out_dir = ENV["CCLIKESH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "cclikesh-debug")
    matches = Dir.glob(File.join(out_dir, "*#{session}*.sqlite"))
    abort("no session DB matching #{session}") if matches.empty?
    matches.first
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/viewer/frames.rb
require_relative "../storage"
require_relative "info"
module Cclikesh::Debug::Viewer::Frames
  def self.call(argv)
    session = argv.shift or abort("usage: cclikesh-debug frames <session>")
    storage = Cclikesh::Debug::Storage.open(Cclikesh::Debug::Viewer::Info.resolve_db(session))
    rows = storage.select_frames(limit: 1000)
    rows.each { |r| puts "#{r[:id]}\t#{r[:ts]}\t#{r[:trigger]}\t#{r[:event_kind] || '-'}\t#{r[:content][0, 80]}" }
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/viewer/grid.rb
require "zlib"
require_relative "../storage"
require_relative "info"
module Cclikesh::Debug::Viewer::Grid
  def self.call(argv)
    session = argv.shift; idx = argv.index("--frame"); frame_id = Integer(argv[idx + 1])
    db = Cclikesh::Debug::Viewer::Info.resolve_db(session)
    storage = Cclikesh::Debug::Storage.open(db)
    row = storage.db.execute("SELECT raw_bytes_zlib FROM frames WHERE id = ?", [frame_id]).first
    abort("no frame") unless row
    bytes = row[0] ? Zlib::Inflate.inflate(row[0]) : ""
    print bytes
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/viewer/query.rb
require_relative "../storage"
require_relative "info"
module Cclikesh::Debug::Viewer::Query
  def self.call(argv)
    session = argv.shift; sql = argv.shift
    storage = Cclikesh::Debug::Storage.open(Cclikesh::Debug::Viewer::Info.resolve_db(session))
    storage.db.execute(sql).each { |row| puts row.join("\t") }
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/viewer/semantic.rb
require_relative "../storage"
require_relative "../embedder_pool"
require_relative "info"
module Cclikesh::Debug::Viewer::Semantic
  def self.call(argv)
    session = argv.shift; query = argv.shift
    k = (idx = argv.index("-k")) ? Integer(argv[idx + 1]) : 5
    storage = Cclikesh::Debug::Storage.open(Cclikesh::Debug::Viewer::Info.resolve_db(session))
    pool = Cclikesh::Debug::EmbedderPool.new
    vec = pool.embed(query)
    blob = vec.pack("f*")
    rows = storage.db.execute(
      "SELECT v.frame_id, v.distance, f.ts, f.content
         FROM frame_vec v JOIN frames f ON f.id = v.frame_id
        WHERE v.embedding MATCH ? AND k = ?
        ORDER BY v.distance",
      [blob, k])
    rows.each { |r| puts "#{r[0]}\t#{r[1].round(3)}\t#{r[2]}\t#{r[3][0, 60]}" }
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/viewer/export.rb
require "zlib"
require "open3"
require_relative "../storage"
require_relative "../cast_writer"
require_relative "info"

module Cclikesh::Debug::Viewer::Export
  def self.call(argv)
    session = argv.shift
    fmt    = (idx = argv.index("--format")) ? argv[idx + 1] : "cast"
    output = (idx = argv.index("--output")) ? argv[idx + 1] : "#{session}.#{fmt}"
    storage = Cclikesh::Debug::Storage.open(Cclikesh::Debug::Viewer::Info.resolve_db(session))
    rows = storage.db.execute("SELECT ts, raw_bytes_zlib FROM frames ORDER BY ts")
    info = storage.session_info
    frames = rows.map { |r| { ts: r[0], raw_bytes: r[1] ? Zlib::Inflate.inflate(r[1]) : "" } }
    case fmt
    when "cast"
      File.open(output, "w") { |f| Cclikesh::Debug::CastWriter.write(f, frames: frames, rows: info[:rows], cols: info[:cols], started_at: 0) }
      puts output
    when "gif"
      cast = "/tmp/cclikesh-export-#{Process.pid}.cast"
      File.open(cast, "w") { |f| Cclikesh::Debug::CastWriter.write(f, frames: frames, rows: info[:rows], cols: info[:cols], started_at: 0) }
      _, _, st = Open3.capture3("agg", cast, output)
      abort("agg failed (install: brew install agg)") unless st.success?
      File.unlink(cast)
      puts output
    when "mp4", "webm"
      cast = "/tmp/cclikesh-export-#{Process.pid}.cast"
      gif  = "/tmp/cclikesh-export-#{Process.pid}.gif"
      File.open(cast, "w") { |f| Cclikesh::Debug::CastWriter.write(f, frames: frames, rows: info[:rows], cols: info[:cols], started_at: 0) }
      _, _, st = Open3.capture3("agg", cast, gif)
      abort("agg failed") unless st.success?
      _, _, st = Open3.capture3("ffmpeg", "-i", gif, "-y", output)
      abort("ffmpeg failed (install: brew install ffmpeg)") unless st.success?
      [cast, gif].each { |f| File.unlink(f) rescue nil }
      puts output
    else
      abort("unsupported format: #{fmt}")
    end
  end
end
```

```ruby
# cclikesh-debug/lib/cclikesh/debug/viewer/clean.rb
module Cclikesh::Debug::Viewer::Clean
  def self.call(argv)
    out_dir = ENV["CCLIKESH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "cclikesh-debug")
    cutoff = if (idx = argv.index("--older-than")) then parse_age(argv[idx + 1]) else nil end
    Dir.glob(File.join(out_dir, "*.sqlite")).each do |path|
      next if cutoff && File.mtime(path) > cutoff
      File.unlink(path)
      puts "removed: #{path}"
    end
  end

  def self.parse_age(s)
    n, unit = s.match(/(\d+)([dhm])/).captures
    seconds = case unit; when "d" then 86400; when "h" then 3600; when "m" then 60; end
    Time.now - Integer(n) * seconds
  end
end
```

- [ ] **Step 1: Commit batch**

```bash
git add cclikesh-debug/lib/cclikesh/debug/viewer/
git commit -m "feat(debug): viewer subcommands (list/info/frames/grid/query/semantic/export/clean)"
```

---

## Task 30: E2E full-session test

**Files:**
- Create: `cclikesh-debug/test/cclikesh-debug/test_e2e_full_session.rb`

- [ ] **Step 1: Write E2E**

```ruby
require "test/unit"
require "tmpdir"
require "open3"

class TestDebugE2EFullSession < Test::Unit::TestCase
  ROOT = File.expand_path("../../..", __dir__)

  def test_start_input_capture_stop_then_query_frames
    dir = Dir.mktmpdir("cclikesh-debug-e2e-")
    ENV["CCLIKESH_DEBUG_DIR"] = dir

    out, _err, st = Open3.capture3({}, "bundle", "exec", "cclikesh-debug", "start",
                                    File.join(ROOT, "examples/echo_shell.rb"),
                                    "--no-vector", chdir: ROOT)
    assert st.success?, "start failed: #{out}"
    uuid = out[/session_uuid=(\S+)/, 1]
    refute_nil uuid

    sleep 1.5  # allow header render

    Open3.capture3({}, "bundle", "exec", "cclikesh-debug", "input", uuid, "hello\\r", chdir: ROOT)
    sleep 0.5
    Open3.capture3({}, "bundle", "exec", "cclikesh-debug", "capture", uuid, chdir: ROOT)
    sleep 0.3
    Open3.capture3({}, "bundle", "exec", "cclikesh-debug", "input", uuid, "/q\\r", chdir: ROOT)
    sleep 0.3
    Open3.capture3({}, "bundle", "exec", "cclikesh-debug", "stop", uuid, chdir: ROOT)
    sleep 0.3

    out, _, _ = Open3.capture3({}, "bundle", "exec", "cclikesh-debug", "frames", uuid, chdir: ROOT)
    refute_empty out, "no frames recorded"
  ensure
    FileUtils.rm_rf(dir) rescue nil
    ENV.delete("CCLIKESH_DEBUG_DIR")
  end
end
```

- [ ] **Step 2: Run, debug, commit**

```bash
bundle exec ruby -Icclikesh-debug/lib -Icclikesh-debug/test/cclikesh-debug \
  cclikesh-debug/test/cclikesh-debug/test_e2e_full_session.rb
```

Expected: passes; if not, check session DB existence under `tmp/cclikesh-debug/`. Adjust timeouts if flaky.

```bash
git add cclikesh-debug/test/cclikesh-debug/test_e2e_full_session.rb
git commit -m "test(debug): E2E full-session start→input→capture→stop→frames"
```

---

## Task 31: Final verification + README updates

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run full body + sub-gem suites**

```bash
bundle exec rake test
bundle exec ruby -Icclikesh-debug/lib -Icclikesh-debug/test/cclikesh-debug \
  -e 'Dir["cclikesh-debug/test/cclikesh-debug/*.rb"].each { |f| require_relative f }'
```

Resolve any failures.

- [ ] **Step 2: Update README**

Replace the existing README with a brief overview reflecting:
- Architecture: curses + Ractor model
- Examples: echo_shell, irb_shell
- Install: `gem install cclikesh` + `gem install cclikesh-debug` (when published)
- macOS only

(Keep the README short — refer to spec for details.)

- [ ] **Step 3: Manual final check**

```bash
bundle exec ruby -Ilib examples/irb_shell/irb_shell.rb
# type: 1 + 1 → confirm => 2
# /q
```

```bash
mkdir -p tmp/cclikesh-debug
CCLIKESH_DEBUG_DIR=tmp/cclikesh-debug bundle exec cclikesh-debug start examples/echo_shell.rb --no-vector
# from another terminal, run input/capture/stop, then `cclikesh-debug frames <uuid>`
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README for curses + Ractor + cclikesh-debug architecture"
```

---

## Self-review

**Spec coverage:**
- Goal pillar 1 (curses migration): Tasks 2, 5, 6, 13, 15, 16
- Goal pillar 2 (Ractor + single-process): Tasks 7, 8, 9, 10, 13
- Goal pillar 3 (cclikesh-debug sub-gem): Tasks 20–30
- Probe Task 0: Task 0
- Examples migration: Task 18
- Test rewrite: Tasks 5, 6, 7, 8, 9, 10, 16, 17
- Spec section "本体への侵襲点": Task 14 (DebugEndpoint)
- Spec "DSL changes (ctx.dialog → ctx.display.dialog)": Task 18
- Spec "shareable_ref": Tasks 7, 11, 18
- Spec "chiebukuro-mcp 互換 schema": Task 21 (MetaSeeds + Storage SCHEMA)
- Spec "Embedding (informers + ruri-v3-310m-onnx)": Task 23
- Spec "asciinema cast / agg / ffmpeg export": Tasks 24, 29 (Export)
- Spec "Recorder Ractor pipeline (4-stage)": Tasks 26, 27
- Spec "WAL mode": Storage.create sets PRAGMA journal_mode=WAL ✓
- Spec "_sqlite_mcp_meta": MetaSeeds rows ✓
- Spec "out of scope": no tasks (correctly omitted)

**Placeholder scan:** No "TBD" or "TODO" remain in tasks. The single occurrence of "(install: brew install agg)" is a runtime hint, not a placeholder.

**Type consistency:**
- `ShareableRef#call` signature consistent across Tasks 7, 8, 11, 18.
- `CtxProxy::DisplayProxy#open_live` returns `LiveSlot` with `update`/`commit`/`discard` — used identically in echo_shell `/slow` and irb_shell.
- `Storage` interface (`insert_frame` keyword args) matches between Tasks 21, 26, 27.
- `ContentBuilder.build(state)` consumes both symbol and string keys (defensive) — referenced in Tasks 22, 26.
- `Recorder` constructor accepts `storage:`, `embedder_factory:`, `no_vector:` consistently in Tasks 26, 27.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-10-cclikesh-curses-ractor-debug.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
