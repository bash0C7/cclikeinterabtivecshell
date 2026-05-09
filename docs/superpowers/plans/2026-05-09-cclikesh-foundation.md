# cclikesh Foundation MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate the ts4r + Ractor architecture end-to-end with a minimal echo shell. This plan covers Plan 1 of the 7-plan cclikesh roadmap. Subsequent plans (dRuby split, full display engine, info layer, command system, logger+Box, example irb_shell) build on this foundation.

**Architecture:** Single-process Ruby program that uses ts4r as the central tuple space. Three Ractors split responsibilities (Render reads `[:render, ...]` tuples and writes to stdout; Input reads stdin lines and writes `[:key, ...]` tuples; the caller's main Ractor dispatches `[:event, :submit, line]` events to the user-supplied `on_submit` block via `Cclikesh::Dispatcher`). The dRuby split (impl ↔ F as separate processes) and reline integration are deferred to Plan 2; this plan uses line-buffered `IO#gets` for input and direct `puts` for display.

**Tech Stack:** Ruby 4.0.3+, ts4r (TupleSpace4Ractor — vendored as a single file because upstream has no gemspec), test-unit, rake, rdoc (stdlib).

**Note on ts4r:** Upstream `seki/ts4r` has no `.gemspec` and is not on rubygems. Bundler git sources require a gemspec. Therefore Plan 1 vendors `src/ts.rb` from `https://github.com/seki/ts4r` (commit `main` at plan time) into `vendor/ts4r.rb` and adds `vendor/` to `$LOAD_PATH` in `lib/cclikesh.rb`. When ts4r becomes a published gem, swap the vendored copy out for a `gem "ts4r"` dependency.

**Out of scope (deferred to later plans):** dRuby, fork+exec, tcsetpgrp, reline raw mode, live slot, dialog, info bar, spinner, idle_phrases, slash full parsing (this plan supports only `/quit`), state store with `on_state_change`, before/after hooks, full logger, Ruby::Box.

---

## File Structure

```
cclikesh/
├── Gemfile
├── cclikesh.gemspec
├── Rakefile
├── .gitignore
├── vendor/
│   └── ts4r.rb              # Verbatim copy of upstream src/ts.rb
├── lib/
│   └── cclikesh/
│       ├── version.rb        # Version constant
│       ├── tuple_space.rb    # ts4r wrapper
│       ├── builder.rb        # DSL block target
│       ├── context.rb        # ctx (display, state, quit)
│       ├── display.rb        # ctx.display.append impl
│       ├── state.rb          # ctx.state[] impl
│       ├── renderer.rb       # display history → IO writer (sync)
│       ├── render_ractor.rb  # Ractor wrapping Renderer
│       ├── input_reader.rb   # gets-based line reader (sync)
│       ├── input_ractor.rb   # Ractor wrapping InputReader
│       ├── dispatcher.rb     # Tuple → handler invocation
│       └── runner.rb         # Cclikesh.run orchestration
├── lib/cclikesh.rb           # Top-level module + autoloads
└── test/
    ├── test_helper.rb
    ├── test_smoke.rb
    ├── test_tuple_space.rb
    ├── test_builder.rb
    ├── test_context.rb
    ├── test_renderer.rb
    ├── test_render_ractor.rb
    ├── test_input_reader.rb
    ├── test_input_ractor.rb
    ├── test_dispatcher.rb
    └── test_runner.rb        # End-to-end echo shell smoke
```

**Responsibility split:**
- `tuple_space.rb`: Thin wrapper around `TupleSpace4Ractor` that adds Ractor.make_shareable and a clean test/production interface. The wrapper exists to give tests a single seam for tuple inspection.
- `builder.rb`: Pure data — stores blocks the user registered. No execution logic.
- `context.rb` / `display.rb` / `state.rb`: User-facing API. Methods translate to tuple writes.
- `renderer.rb` (sync) / `render_ractor.rb` (async): Renderer is testable without spawning Ractors. RenderRactor wraps it.
- `input_reader.rb` (sync) / `input_ractor.rb` (async): Same split.
- `dispatcher.rb`: Pulls events off the tuple space and calls user blocks.
- `runner.rb`: `Cclikesh.run` glue — builds Builder, spawns Ractors, runs the dispatcher, handles shutdown.

---

## Task 1: Project Skeleton + Smoke Test

**Files:**
- Create: `Gemfile`
- Create: `cclikesh.gemspec`
- Create: `Rakefile`
- Create: `.gitignore`
- Create: `lib/cclikesh.rb`
- Create: `lib/cclikesh/version.rb`
- Create: `test/test_helper.rb`
- Create: `test/test_smoke.rb`

- [ ] **Step 1: Create `.gitignore`**

```
/.bundle/
/vendor/bundle
/Gemfile.lock
/tmp/
*.gem
*.rbc
.DS_Store
```

- [ ] **Step 2: Create `lib/cclikesh/version.rb`**

```ruby
# frozen_string_literal: true

module Cclikesh
  VERSION = "0.1.0"
end
```

- [ ] **Step 3: Create `lib/cclikesh.rb`**

```ruby
# frozen_string_literal: true

# Make the vendored ts4r available as `require "ts4r"`.
$LOAD_PATH.unshift(File.expand_path("../vendor", __dir__))

require_relative "cclikesh/version"

module Cclikesh
end
```

- [ ] **Step 4: Create `cclikesh.gemspec`**

```ruby
# frozen_string_literal: true

require_relative "lib/cclikesh/version"

Gem::Specification.new do |spec|
  spec.name          = "cclikesh"
  spec.version       = Cclikesh::VERSION
  spec.authors       = ["bash0C7"]
  spec.summary       = "Claude Code-style 3-region interactive CLI shell framework"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files         = Dir["lib/**/*.rb", "vendor/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # ts4r is vendored at vendor/ts4r.rb; no runtime gem dependency on it yet.

  spec.add_development_dependency "test-unit", "~> 3.6"
  spec.add_development_dependency "rake", "~> 13.0"
end
```

- [ ] **Step 5: Create `Gemfile`**

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# ts4r is vendored at vendor/ts4r.rb (upstream has no gemspec). When ts4r is
# published to rubygems, replace the vendored copy with `gem "ts4r"` here.
```

- [ ] **Step 6: Create `Rakefile`**

```ruby
# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: :test
```

- [ ] **Step 7: Create `test/test_helper.rb`**

```ruby
# frozen_string_literal: true

require "test/unit"
require "cclikesh"
```

- [ ] **Step 8: Create `test/test_smoke.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestSmoke < Test::Unit::TestCase
  def test_version_is_defined
    assert_match(/\A\d+\.\d+\.\d+\z/, Cclikesh::VERSION)
  end

  def test_module_loadable
    assert_equal Module, Cclikesh.class
  end
end
```

- [ ] **Step 9: Run `bundle install`**

Run: `bundle install`
Expected: Successful install of ts4r from git, test-unit, rake. No errors.

- [ ] **Step 10: Run the smoke test, expect PASS**

Run: `bundle exec rake test`
Expected: 2 assertions, 2 passes. Output ends with `2 tests, 2 assertions, 0 failures, 0 errors`.

- [ ] **Step 11: Commit**

```bash
git add Gemfile cclikesh.gemspec Rakefile .gitignore lib/ test/
git commit -m "feat: add project skeleton with smoke test"
```

---

## Task 2: TupleSpace Wrapper

**Files:**
- Create: `vendor/ts4r.rb` (verbatim copy of upstream `seki/ts4r` `src/ts.rb`)
- Create: `lib/cclikesh/tuple_space.rb`
- Create: `test/test_tuple_space.rb`

- [ ] **Step 0: Vendor ts4r**

Download `src/ts.rb` from `seki/ts4r` (main branch) and save it as `vendor/ts4r.rb`. This is needed because upstream has no gemspec, so it cannot be a Bundler git source. The `lib/cclikesh.rb` from Task 1 already prepends `vendor/` to `$LOAD_PATH`, so `require "ts4r"` resolves to the vendored copy.

Run:
```bash
mkdir -p vendor
gh api repos/seki/ts4r/contents/src/ts.rb -H "Accept: application/vnd.github.raw" > vendor/ts4r.rb
```

Verify the file defines `class TupleSpace4Ractor`:
```bash
grep -E "^class TupleSpace4Ractor" vendor/ts4r.rb
```
Expected: one matching line.

- [ ] **Step 1: Write the failing test in `test/test_tuple_space.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"

class TestTupleSpace < Test::Unit::TestCase
  def test_write_then_take_returns_tuple
    ts = Cclikesh::TupleSpace.new
    ts.write([:hello, "world"])
    assert_equal [:hello, "world"], ts.take([:hello, nil])
  end

  def test_take_with_pattern_match
    ts = Cclikesh::TupleSpace.new
    ts.write([:event, :submit, "x = 1"])
    assert_equal [:event, :submit, "x = 1"], ts.take([:event, :submit, nil])
  end

  def test_read_does_not_consume
    ts = Cclikesh::TupleSpace.new
    ts.write([:hello, "world"])
    assert_equal [:hello, "world"], ts.read([:hello, nil])
    assert_equal [:hello, "world"], ts.read([:hello, nil])
  end

  def test_is_ractor_shareable
    ts = Cclikesh::TupleSpace.new
    assert Ractor.shareable?(ts), "TupleSpace must be Ractor-shareable"
  end
end
```

- [ ] **Step 2: Run the test, verify it fails with LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_tuple_space.rb`
Expected: FAIL with `cannot load such file -- cclikesh/tuple_space (LoadError)`.

- [ ] **Step 3: Implement `lib/cclikesh/tuple_space.rb`**

```ruby
# frozen_string_literal: true

require "ts4r"

module Cclikesh
  class TupleSpace
    def self.new
      Ractor.make_shareable(TupleSpace4Ractor.new)
    end
  end
end
```

Note: `Cclikesh::TupleSpace.new` returns a frozen, shareable `TupleSpace4Ractor` instance. We use `def self.new` to override the default constructor entirely; callers do not get a `Cclikesh::TupleSpace` instance, they get the underlying `TupleSpace4Ractor` already prepared for cross-Ractor use.

- [ ] **Step 4: Run the test, verify all 4 assertions PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_tuple_space.rb`
Expected: `4 tests, 4 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add vendor/ts4r.rb lib/cclikesh/tuple_space.rb test/test_tuple_space.rb
git commit -m "feat: vendor ts4r and add TupleSpace wrapper"
```

---

## Task 3: Builder DSL

**Files:**
- Create: `lib/cclikesh/builder.rb`
- Create: `test/test_builder.rb`

- [ ] **Step 1: Write the failing test in `test/test_builder.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/builder"

class TestBuilder < Test::Unit::TestCase
  def test_on_submit_stores_block
    b = Cclikesh::Builder.new
    block = proc { |line, ctx| line.upcase }
    b.on_submit(&block)
    assert_same block, b.on_submit_handler
  end

  def test_on_submit_called_twice_replaces
    b = Cclikesh::Builder.new
    b.on_submit { |line, ctx| 1 }
    second = proc { |line, ctx| 2 }
    b.on_submit(&second)
    assert_same second, b.on_submit_handler
  end

  def test_slash_stores_per_name_handler
    b = Cclikesh::Builder.new
    quit_block = proc { |args, ctx| ctx.quit }
    b.slash(:quit, &quit_block)
    assert_same quit_block, b.slash_handler(:quit)
  end

  def test_slash_handler_unknown_returns_nil
    b = Cclikesh::Builder.new
    assert_nil b.slash_handler(:nope)
  end

  def test_slash_accepts_string_name_normalized_to_symbol
    b = Cclikesh::Builder.new
    block = proc { |args, ctx| nil }
    b.slash("quit", &block)
    assert_same block, b.slash_handler(:quit)
  end
end
```

- [ ] **Step 2: Run the test, verify it fails with LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_builder.rb`
Expected: FAIL with `cannot load such file -- cclikesh/builder`.

- [ ] **Step 3: Implement `lib/cclikesh/builder.rb`**

```ruby
# frozen_string_literal: true

module Cclikesh
  class Builder
    attr_reader :on_submit_handler

    def initialize
      @on_submit_handler = nil
      @slash_handlers = {}
    end

    def on_submit(&block)
      @on_submit_handler = block
    end

    def slash(name, &block)
      @slash_handlers[name.to_sym] = block
    end

    def slash_handler(name)
      @slash_handlers[name.to_sym]
    end
  end
end
```

- [ ] **Step 4: Run the test, verify 5 assertions PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_builder.rb`
Expected: `5 tests, 5 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/builder.rb test/test_builder.rb
git commit -m "feat: add Builder DSL with on_submit and slash"
```

---

## Task 4: Display (writes display tuples)

**Files:**
- Create: `lib/cclikesh/display.rb`
- Create: `test/test_display.rb`

- [ ] **Step 1: Write the failing test in `test/test_display.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/display"

class TestDisplay < Test::Unit::TestCase
  def test_append_writes_render_tuple
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)
    d.append("hello")
    assert_equal [:render, :display_append, "hello", {}], ts.take([:render, :display_append, nil, nil])
  end

  def test_append_with_style_and_prompt
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)
    d.append("=> 42", style: :result)
    d.append("x = 1", prompt: "irb> ")
    assert_equal [:render, :display_append, "=> 42", {style: :result}],
                 ts.take([:render, :display_append, "=> 42", nil])
    assert_equal [:render, :display_append, "x = 1", {prompt: "irb> "}],
                 ts.take([:render, :display_append, "x = 1", nil])
  end
end
```

- [ ] **Step 2: Run the test, verify LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_display.rb`
Expected: FAIL with `cannot load such file -- cclikesh/display`.

- [ ] **Step 3: Implement `lib/cclikesh/display.rb`**

```ruby
# frozen_string_literal: true

module Cclikesh
  class Display
    def initialize(tuple_space)
      @ts = tuple_space
    end

    def append(text, style: nil, prompt: nil)
      opts = {}
      opts[:style] = style if style
      opts[:prompt] = prompt if prompt
      @ts.write([:render, :display_append, text, opts])
    end
  end
end
```

- [ ] **Step 4: Run the test, verify PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_display.rb`
Expected: `2 tests, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/display.rb test/test_display.rb
git commit -m "feat: add Display with append writing render tuples"
```

---

## Task 5: State (read/write via tuple space)

**Files:**
- Create: `lib/cclikesh/state.rb`
- Create: `test/test_state.rb`

- [ ] **Step 1: Write the failing test in `test/test_state.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/state"

class TestState < Test::Unit::TestCase
  def test_set_and_get
    ts = Cclikesh::TupleSpace.new
    s = Cclikesh::State.new(ts)
    s[:phase] = :working
    assert_equal :working, s[:phase]
  end

  def test_get_unset_returns_nil
    ts = Cclikesh::TupleSpace.new
    s = Cclikesh::State.new(ts)
    assert_nil s[:nope]
  end

  def test_set_overwrites
    ts = Cclikesh::TupleSpace.new
    s = Cclikesh::State.new(ts)
    s[:phase] = :working
    s[:phase] = :idle
    assert_equal :idle, s[:phase]
  end
end
```

Implementation note: For reads when no value exists, we cannot use ts4r `take` because it blocks. Use `read` with a brief polling pattern, or maintain a `[:state, key, :unset]` sentinel. Simplest correct path: write a sentinel for every key on first set, and use `read` (which is non-consuming). For "get unset", we use `read` against the pattern with timeout — but ts4r's `read` blocks. So we maintain an in-memory side cache as a frozen Hash that gets updated atomically with each write, and use that for reads. See the implementation for the trade-off.

For Plan 1 simplicity, we lean on the fact that `Cclikesh::State` is only invoked from the main Ractor (handlers run there). We keep an in-process Hash for fast reads and write tuples for cross-Ractor visibility.

- [ ] **Step 2: Run the test, verify LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_state.rb`
Expected: FAIL with `cannot load such file -- cclikesh/state`.

- [ ] **Step 3: Implement `lib/cclikesh/state.rb`**

```ruby
# frozen_string_literal: true

module Cclikesh
  class State
    def initialize(tuple_space)
      @ts = tuple_space
      @cache = {}
    end

    def [](key)
      @cache[key.to_sym]
    end

    def []=(key, value)
      sym = key.to_sym
      old = @cache[sym]
      @cache[sym] = value
      @ts.write([:state, sym, value])
      @ts.write([:event, :state_change, sym, old, value]) if old != value
    end
  end
end
```

- [ ] **Step 4: Run the test, verify PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_state.rb`
Expected: `3 tests, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/state.rb test/test_state.rb
git commit -m "feat: add State store with cache and tuple write"
```

---

## Task 6: Context (ctx) — Display + State + quit

**Files:**
- Create: `lib/cclikesh/context.rb`
- Create: `test/test_context.rb`

- [ ] **Step 1: Write the failing test in `test/test_context.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/context"

class TestContext < Test::Unit::TestCase
  def test_display_returns_a_display
    ts = Cclikesh::TupleSpace.new
    c = Cclikesh::Context.new(ts)
    assert_kind_of Cclikesh::Display, c.display
  end

  def test_state_returns_a_state
    ts = Cclikesh::TupleSpace.new
    c = Cclikesh::Context.new(ts)
    assert_kind_of Cclikesh::State, c.state
  end

  def test_quit_writes_cmd_quit_tuple
    ts = Cclikesh::TupleSpace.new
    c = Cclikesh::Context.new(ts)
    c.quit
    assert_equal [:cmd, :quit], ts.take([:cmd, :quit])
  end

  def test_display_and_state_are_memoized
    ts = Cclikesh::TupleSpace.new
    c = Cclikesh::Context.new(ts)
    assert_same c.display, c.display
    assert_same c.state, c.state
  end
end
```

- [ ] **Step 2: Run the test, verify LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_context.rb`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/cclikesh/context.rb`**

```ruby
# frozen_string_literal: true

require_relative "display"
require_relative "state"

module Cclikesh
  class Context
    def initialize(tuple_space)
      @ts = tuple_space
    end

    def display
      @display ||= Display.new(@ts)
    end

    def state
      @state ||= State.new(@ts)
    end

    def quit
      @ts.write([:cmd, :quit])
    end
  end
end
```

- [ ] **Step 4: Run the test, verify PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_context.rb`
Expected: `4 tests, 5 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/context.rb test/test_context.rb
git commit -m "feat: add Context with display, state, and quit"
```

---

## Task 7: Renderer (sync) — render display history to IO

**Files:**
- Create: `lib/cclikesh/renderer.rb`
- Create: `test/test_renderer.rb`

The Renderer is sync (no Ractor) so it can be unit-tested without timing concerns. It accepts a tuple space and an output IO. The test injects a `StringIO` to inspect output.

- [ ] **Step 1: Write the failing test in `test/test_renderer.rb`**

```ruby
# frozen_string_literal: true

require "stringio"
require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/renderer"

class TestRenderer < Test::Unit::TestCase
  def test_processes_one_pending_append
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)
    ts.write([:render, :display_append, "hello", {}])
    r.render_pending
    assert_equal "hello\n", out.string
  end

  def test_processes_multiple_pending_appends_in_order
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)
    ts.write([:render, :display_append, "first", {}])
    ts.write([:render, :display_append, "second", {}])
    r.render_pending
    assert_equal "first\nsecond\n", out.string
  end

  def test_render_pending_with_no_tuples_does_not_block
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)
    r.render_pending
    assert_equal "", out.string
  end

  def test_appends_prompt_prefix_when_present
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)
    ts.write([:render, :display_append, "x = 1", {prompt: "irb> "}])
    r.render_pending
    assert_equal "irb> x = 1\n", out.string
  end
end
```

The third test (`render_pending_with_no_tuples_does_not_block`) is critical — `render_pending` must drain whatever is queued and then return. It must NOT block waiting for new tuples. We achieve this by using a sentinel write before the drain loop, and breaking when we see the sentinel.

- [ ] **Step 2: Run the test, verify LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_renderer.rb`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/cclikesh/renderer.rb`**

```ruby
# frozen_string_literal: true

module Cclikesh
  class Renderer
    SENTINEL = [:render, :__drain_sentinel__, nil, nil].freeze

    def initialize(tuple_space, output_io)
      @ts = tuple_space
      @out = output_io
    end

    # Drain all currently-queued render tuples and write them to output.
    # Non-blocking: writes a sentinel first, then takes until the sentinel
    # is consumed.
    def render_pending
      sentinel_id = Object.new.object_id
      @ts.write([:render, :__drain_sentinel__, sentinel_id, nil])
      loop do
        tuple = @ts.take([:render, nil, nil, nil])
        break if tuple[1] == :__drain_sentinel__ && tuple[2] == sentinel_id
        process(tuple)
      end
    end

    private

    def process(tuple)
      _, op, payload, opts = tuple
      case op
      when :display_append
        prefix = (opts && opts[:prompt]) || ""
        @out.puts("#{prefix}#{payload}")
      end
    end
  end
end
```

The sentinel pattern: `render_pending` writes a uniquely-identified sentinel tuple, then drains the `[:render, ...]` queue in order. When it sees its own sentinel, it stops. Other tuples sandwiched in are processed; tuples that arrive *after* this drain remain for the next `render_pending` call.

- [ ] **Step 4: Run the test, verify PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_renderer.rb`
Expected: `4 tests, 4 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/renderer.rb test/test_renderer.rb
git commit -m "feat: add sync Renderer that drains render tuples"
```

---

## Task 8: RenderRactor — Ractor wrapping Renderer with periodic tick

**Files:**
- Create: `lib/cclikesh/render_ractor.rb`
- Create: `test/test_render_ractor.rb`

- [ ] **Step 1: Write the failing test in `test/test_render_ractor.rb`**

```ruby
# frozen_string_literal: true

require "stringio"
require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/render_ractor"

class TestRenderRactor < Test::Unit::TestCase
  def test_emits_rendered_after_processing
    ts = Cclikesh::TupleSpace.new
    out_path = "tmp/test_render_ractor_out.txt"
    Dir.mkdir("tmp") unless Dir.exist?("tmp")
    File.write(out_path, "")
    File.open(out_path, "w") do |f|
      ractor = Cclikesh::RenderRactor.start(ts, f, tick_interval: 0.02)
      ts.write([:render, :display_append, "hi", {}])
      # Wait for rendered acknowledgment
      _, frame_id = ts.take([:rendered, nil])
      assert_kind_of Integer, frame_id
      ts.write([:cmd, :quit])
      ractor.value rescue nil
    end
    assert_equal "hi\n", File.read(out_path)
  end
end
```

We use a real file (not StringIO) because StringIO is not Ractor-shareable. Real `File` objects are usable across Ractors when wrapped via Ractor.shareable patterns; in our case the file is opened in the parent and the Ractor receives the path.

Actually, even File objects are not freely shareable. Use the path-and-reopen pattern: the Ractor opens the file itself.

Revised test:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/render_ractor"

class TestRenderRactor < Test::Unit::TestCase
  def setup
    Dir.mkdir("tmp") unless Dir.exist?("tmp")
    @out_path = "tmp/test_render_ractor_#{Process.pid}_#{rand(99999)}.txt"
    File.write(@out_path, "")
  end

  def teardown
    File.unlink(@out_path) if @out_path && File.exist?(@out_path)
  end

  def test_emits_rendered_after_processing_appends
    ts = Cclikesh::TupleSpace.new
    ractor = Cclikesh::RenderRactor.start(ts, @out_path, tick_interval: 0.02)
    ts.write([:render, :display_append, "hi", {}])
    _, frame_id = ts.take([:rendered, nil])
    assert_kind_of Integer, frame_id
    ts.write([:cmd, :quit])
    ractor.value rescue nil
    assert_equal "hi\n", File.read(@out_path)
  end

  def test_processes_multiple_appends_in_order
    ts = Cclikesh::TupleSpace.new
    ractor = Cclikesh::RenderRactor.start(ts, @out_path, tick_interval: 0.02)
    ts.write([:render, :display_append, "a", {}])
    ts.write([:render, :display_append, "b", {}])
    # wait for at least one render that processed both
    deadline = Time.now + 1.0
    until File.read(@out_path).include?("b\n")
      flunk "render_ractor did not process both appends within 1s" if Time.now > deadline
      ts.take([:rendered, nil])
    end
    ts.write([:cmd, :quit])
    ractor.value rescue nil
    assert_equal "a\nb\n", File.read(@out_path)
  end
end
```

- [ ] **Step 2: Run the test, verify LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_render_ractor.rb`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/cclikesh/render_ractor.rb`**

```ruby
# frozen_string_literal: true

require_relative "renderer"

module Cclikesh
  class RenderRactor
    # Spawns a Ractor that periodically renders pending tuples from `ts` to
    # the file at `output_path` (opened in append mode inside the Ractor).
    # The Ractor terminates when [:cmd, :quit] is observed.
    def self.start(ts, output_path, tick_interval: 0.06)
      Ractor.new(ts, output_path, tick_interval) do |ts, output_path, tick_interval|
        require "cclikesh/renderer"
        File.open(output_path, "a") do |out|
          renderer = Cclikesh::Renderer.new(ts, out)
          frame_id = 0
          loop do
            sleep tick_interval
            renderer.render_pending
            out.flush
            frame_id += 1
            ts.write([:rendered, frame_id])
            quit_seen = ts.read([:cmd, :quit]) rescue nil
            # The above rescue isn't sufficient because ts.read blocks.
            # Use the take+rewrite trick:
            quit = ts_try_read_quit(ts)
            break if quit
          end
        end
      end
    end

    # Helper used inside the Ractor body — defined as a lambda assigned
    # to a constant so the Ractor can reach it.
    def self.ts_try_read_quit(ts)
      # ts4r read blocks; emulate non-blocking by take + immediate rewrite.
      tuple = ts.take([:cmd, :quit])
      ts.write(tuple)
      true
    end
  end
end
```

There's a problem: `ts.take([:cmd, :quit])` blocks if no such tuple exists. We need a non-blocking check. ts4r's `take`/`read` block. Workaround: spawn a separate "quit watcher" sub-Ractor that takes the quit and notifies. Or: use the take-then-rewrite pattern — but only after we know quit is there.

Simpler approach: have the Render Ractor also `take` `[:render, ...]` — but we already drain those each tick. The quit signal needs a non-blocking peek.

**Reset the design:** instead of polling for `[:cmd, :quit]`, the Render Ractor watches for a tuple type that's _only_ present when shutting down. Have the parent write `[:render_ractor_stop]` directly to the Render Ractor via Ractor message (not the tuple space). Use `Ractor#send` and `Ractor.receive_if` inside the loop.

Revised implementation:

```ruby
# frozen_string_literal: true

require_relative "renderer"

module Cclikesh
  class RenderRactor
    def self.start(ts, output_path, tick_interval: 0.06)
      Ractor.new(ts, output_path, tick_interval) do |ts, output_path, tick_interval|
        require "cclikesh/renderer"
        File.open(output_path, "a") do |out|
          renderer = Cclikesh::Renderer.new(ts, out)
          frame_id = 0
          stopping = false
          until stopping
            sleep tick_interval
            renderer.render_pending
            out.flush
            frame_id += 1
            ts.write([:rendered, frame_id])
            # Non-blocking peek for stop message via Ractor port
            begin
              msg = Ractor.receive_if { |m| m == :stop }
              stopping = true if msg == :stop
            rescue Ractor::Error
              # No matching message; keep going.
            end
          end
        end
      end
    end

    def self.stop(ractor)
      ractor.send(:stop)
    end
  end
end
```

But `Ractor.receive_if` blocks until a matching message arrives. We need non-blocking. In Ruby 4.0, `Ractor::Port#receive` blocks; `Port#try_recv` (if it exists) is non-blocking. Without that primitive, simplest pattern: have a 2nd Ractor watch `[:cmd, :quit]` and `Ractor#close` the render Ractor on detection.

**Simplest correct approach for Plan 1:** Fork a thread inside the Render Ractor that listens for `[:cmd, :quit]` and sets an instance variable. Threads inside Ractors are allowed (unlike across).

```ruby
# frozen_string_literal: true

require_relative "renderer"

module Cclikesh
  class RenderRactor
    def self.start(ts, output_path, tick_interval: 0.06)
      Ractor.new(ts, output_path, tick_interval) do |ts, output_path, tick_interval|
        require "cclikesh/renderer"
        File.open(output_path, "a") do |out|
          renderer = Cclikesh::Renderer.new(ts, out)
          frame_id = 0
          stopping = false
          # Quit watcher thread inside this Ractor
          watcher = Thread.new do
            ts.read([:cmd, :quit])  # blocks until quit is written
            stopping = true
          end
          loop do
            break if stopping
            sleep tick_interval
            renderer.render_pending
            out.flush
            frame_id += 1
            ts.write([:rendered, frame_id])
          end
          watcher.kill
        end
      end
    end
  end
end
```

This works because `[:cmd, :quit]` is written and `read` (non-consuming) returns it; the watcher thread sets `stopping`, the main loop in the Ractor sees `stopping=true` on next iteration and breaks.

- [ ] **Step 4: Run the test, verify PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_render_ractor.rb`
Expected: `2 tests, X assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/render_ractor.rb test/test_render_ractor.rb
git commit -m "feat: add RenderRactor with tick loop and quit watcher"
```

---

## Task 9: InputReader (sync) — line-buffered stdin reader

**Files:**
- Create: `lib/cclikesh/input_reader.rb`
- Create: `test/test_input_reader.rb`

- [ ] **Step 1: Write the failing test in `test/test_input_reader.rb`**

```ruby
# frozen_string_literal: true

require "stringio"
require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/input_reader"

class TestInputReader < Test::Unit::TestCase
  def test_reads_one_line_and_writes_key_tuple
    ts = Cclikesh::TupleSpace.new
    input = StringIO.new("hello\n")
    r = Cclikesh::InputReader.new(ts, input)
    r.read_one
    assert_equal [:key, "hello"], ts.take([:key, nil])
  end

  def test_strips_trailing_newline_only
    ts = Cclikesh::TupleSpace.new
    input = StringIO.new("  spaces  \n")
    r = Cclikesh::InputReader.new(ts, input)
    r.read_one
    assert_equal [:key, "  spaces  "], ts.take([:key, nil])
  end

  def test_eof_writes_nil_key
    ts = Cclikesh::TupleSpace.new
    input = StringIO.new("")
    r = Cclikesh::InputReader.new(ts, input)
    r.read_one
    assert_equal [:key, nil], ts.take([:key, nil])
  end
end
```

- [ ] **Step 2: Run the test, verify LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_input_reader.rb`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/cclikesh/input_reader.rb`**

```ruby
# frozen_string_literal: true

module Cclikesh
  class InputReader
    def initialize(tuple_space, input_io)
      @ts = tuple_space
      @in = input_io
    end

    def read_one
      line = @in.gets
      payload = line.nil? ? nil : line.chomp
      @ts.write([:key, payload])
    end
  end
end
```

- [ ] **Step 4: Run the test, verify PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_input_reader.rb`
Expected: `3 tests, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/input_reader.rb test/test_input_reader.rb
git commit -m "feat: add InputReader for line-buffered stdin"
```

---

## Task 10: InputRactor — Ractor wrapping InputReader

**Files:**
- Create: `lib/cclikesh/input_ractor.rb`
- Create: `test/test_input_ractor.rb`

- [ ] **Step 1: Write the failing test in `test/test_input_ractor.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/input_ractor"

class TestInputRactor < Test::Unit::TestCase
  def setup
    Dir.mkdir("tmp") unless Dir.exist?("tmp")
    @input_path = "tmp/test_input_ractor_#{Process.pid}_#{rand(99999)}.txt"
  end

  def teardown
    File.unlink(@input_path) if @input_path && File.exist?(@input_path)
  end

  def test_emits_key_tuples_for_each_line
    File.write(@input_path, "first\nsecond\n")
    ts = Cclikesh::TupleSpace.new
    Cclikesh::InputRactor.start(ts, @input_path)
    assert_equal [:key, "first"], ts.take([:key, nil])
    assert_equal [:key, "second"], ts.take([:key, nil])
    assert_equal [:key, nil], ts.take([:key, nil])  # EOF sentinel
  end
end
```

- [ ] **Step 2: Run the test, verify LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_input_ractor.rb`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/cclikesh/input_ractor.rb`**

```ruby
# frozen_string_literal: true

module Cclikesh
  class InputRactor
    def self.start(ts, input_path)
      Ractor.new(ts, input_path) do |ts, input_path|
        require "cclikesh/input_reader"
        File.open(input_path, "r") do |input|
          reader = Cclikesh::InputReader.new(ts, input)
          loop do
            reader.read_one
            tuple = ts.read([:key, nil])
            break if tuple[1].nil?  # EOF sentinel observed
          end
        end
      end
    end
  end
end
```

The above has a subtle issue: `ts.read([:key, nil])` returns the most recently written `[:key, ...]` (or any matching one). After we write `[:key, nil]` for EOF, the read might return some earlier non-nil key. Use a different approach: track within the Ractor.

```ruby
# frozen_string_literal: true

module Cclikesh
  class InputRactor
    def self.start(ts, input_path)
      Ractor.new(ts, input_path) do |ts, input_path|
        require "cclikesh/input_reader"
        File.open(input_path, "r") do |input|
          reader = Cclikesh::InputReader.new(ts, input)
          loop do
            line = input.gets
            payload = line.nil? ? nil : line.chomp
            ts.write([:key, payload])
            break if payload.nil?
          end
        end
      end
    end
  end
end
```

We sidestep using InputReader inside the Ractor (since it's the same logic) — instead inline the read+write. InputReader is still tested separately as the unit.

Alternatively, keep InputReader and pass a flag back. The cleanest: rewrite InputReader to return `(payload, eof?)`:

For Plan 1 simplicity: inline the logic inside InputRactor. The InputReader unit test still validates the read-and-write behavior. Note in code that this duplication is intentional for Ractor compatibility (closures cannot capture InputReader instance across the Ractor boundary cleanly).

- [ ] **Step 4: Run the test, verify PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_input_ractor.rb`
Expected: `1 tests, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/input_ractor.rb test/test_input_ractor.rb
git commit -m "feat: add InputRactor reading lines into tuple space"
```

---

## Task 11: Dispatcher — convert key tuples into events and invoke handlers

**Files:**
- Create: `lib/cclikesh/dispatcher.rb`
- Create: `test/test_dispatcher.rb`

The Dispatcher runs in the caller's main Ractor (so it can call Builder's blocks, which capture closures). It pulls `[:key, payload]` tuples and either:
- writes `[:event, :submit, line]` and invokes `on_submit_handler` with `(line, ctx)`
- if line starts with `/`, writes `[:event, :slash, name, args]` and invokes `slash_handler(:name)`

For Plan 1, only `/quit` is supported as a slash. Unknown slash → display an error.

- [ ] **Step 1: Write the failing test in `test/test_dispatcher.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/builder"
require "cclikesh/context"
require "cclikesh/dispatcher"

class TestDispatcher < Test::Unit::TestCase
  def test_dispatch_one_calls_on_submit_handler
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    received = []
    builder.on_submit { |line, ctx| received << line }
    ts.write([:key, "hello"])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    d.dispatch_one
    assert_equal ["hello"], received
  end

  def test_dispatch_one_calls_slash_handler_for_known_command
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    quit_called = false
    builder.slash(:quit) { |args, ctx| quit_called = true; ctx.quit }
    ts.write([:key, "/quit"])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    d.dispatch_one
    assert quit_called, "slash handler must be called"
  end

  def test_dispatch_one_writes_error_for_unknown_slash
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    ts.write([:key, "/unknown"])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    d.dispatch_one
    tuple = ts.take([:render, :display_append, nil, nil])
    assert_equal :display_append, tuple[1]
    assert_match(/unknown/, tuple[2])
  end

  def test_dispatch_one_returns_quit_when_eof_key_seen
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    ts.write([:key, nil])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    result = d.dispatch_one
    assert_equal :quit, result
  end

  def test_dispatch_one_with_no_on_submit_does_not_raise
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    ts.write([:key, "hello"])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    assert_nothing_raised { d.dispatch_one }
  end
end
```

- [ ] **Step 2: Run the test, verify LoadError**

Run: `bundle exec ruby -Ilib -Itest test/test_dispatcher.rb`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/cclikesh/dispatcher.rb`**

```ruby
# frozen_string_literal: true

module Cclikesh
  class Dispatcher
    def initialize(tuple_space, builder, context)
      @ts = tuple_space
      @builder = builder
      @ctx = context
    end

    # Pull one [:key, payload] off the tuple space and dispatch.
    # Returns :quit if EOF was seen, nil otherwise.
    def dispatch_one
      _, payload = @ts.take([:key, nil])
      return :quit if payload.nil?

      if payload.start_with?("/")
        dispatch_slash(payload)
      else
        dispatch_submit(payload)
      end
      nil
    end

    private

    def dispatch_submit(line)
      @ts.write([:event, :submit, line])
      handler = @builder.on_submit_handler
      handler.call(line, @ctx) if handler
    end

    def dispatch_slash(payload)
      name_part, *args = payload[1..].split(/\s+/)
      name = name_part.to_sym
      @ts.write([:event, :slash, name, args])
      handler = @builder.slash_handler(name)
      if handler
        handler.call(args, @ctx)
      else
        @ctx.display.append("/#{name}: not registered", style: :error)
      end
    end
  end
end
```

- [ ] **Step 4: Run the test, verify PASS**

Run: `bundle exec ruby -Ilib -Itest test/test_dispatcher.rb`
Expected: `5 tests, 6 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/dispatcher.rb test/test_dispatcher.rb
git commit -m "feat: add Dispatcher with on_submit and slash routing"
```

---

## Task 12: Runner — Cclikesh.run orchestration

**Files:**
- Create: `lib/cclikesh/runner.rb`
- Modify: `lib/cclikesh.rb`
- Create: `test/test_runner.rb`

The Runner ties everything together. `Cclikesh.run`:
1. Yields a `Builder` to the caller's block (registration).
2. Creates a TupleSpace.
3. Spawns RenderRactor (writing to `output_path`, default stdout-substitute file) and InputRactor (reading from `input_path`, default stdin-substitute file).
4. Creates Context.
5. Creates Dispatcher.
6. Loops calling `dispatcher.dispatch_one` until `:quit` is returned or `[:cmd, :quit]` is observed.
7. Cleans up Ractors.

For Plan 1, the Runner accepts `input_path:` and `output_path:` keyword args to enable end-to-end testing with files.

- [ ] **Step 1: Write the failing test in `test/test_runner.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh"

class TestRunner < Test::Unit::TestCase
  def setup
    Dir.mkdir("tmp") unless Dir.exist?("tmp")
    pid_rand = "#{Process.pid}_#{rand(99999)}"
    @input_path = "tmp/test_runner_in_#{pid_rand}.txt"
    @output_path = "tmp/test_runner_out_#{pid_rand}.txt"
    File.write(@output_path, "")
  end

  def teardown
    [@input_path, @output_path].each do |p|
      File.unlink(p) if p && File.exist?(p)
    end
  end

  def test_echo_shell_end_to_end
    File.write(@input_path, "hello\n/quit\n")
    Cclikesh.run(input_path: @input_path, output_path: @output_path) do |shell|
      shell.on_submit { |line, ctx| ctx.display.append("you said: #{line}") }
      shell.slash(:quit) { |args, ctx| ctx.quit }
    end
    assert_equal "you said: hello\n", File.read(@output_path)
  end

  def test_unknown_slash_renders_error
    File.write(@input_path, "/nope\n/quit\n")
    Cclikesh.run(input_path: @input_path, output_path: @output_path) do |shell|
      shell.slash(:quit) { |args, ctx| ctx.quit }
    end
    assert_match(/nope.*not registered/, File.read(@output_path))
  end

  def test_eof_terminates_loop
    File.write(@input_path, "alpha\n")
    Cclikesh.run(input_path: @input_path, output_path: @output_path) do |shell|
      shell.on_submit { |line, ctx| ctx.display.append(line) }
    end
    assert_equal "alpha\n", File.read(@output_path)
  end
end
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/test_runner.rb`
Expected: FAIL with `NoMethodError: undefined method 'run'` (or similar).

- [ ] **Step 3: Implement `lib/cclikesh/runner.rb`**

```ruby
# frozen_string_literal: true

require_relative "tuple_space"
require_relative "builder"
require_relative "context"
require_relative "dispatcher"
require_relative "render_ractor"
require_relative "input_ractor"

module Cclikesh
  class Runner
    def self.run(input_path:, output_path:, tick_interval: 0.06, &block)
      builder = Builder.new
      block.call(builder)

      ts = TupleSpace.new
      ctx = Context.new(ts)
      dispatcher = Dispatcher.new(ts, builder, ctx)

      render_ractor = RenderRactor.start(ts, output_path, tick_interval: tick_interval)
      InputRactor.start(ts, input_path)

      loop do
        result = dispatcher.dispatch_one
        break if result == :quit
        break if quit_requested?(ts)
      end

      ts.write([:cmd, :quit]) unless quit_requested?(ts)
      render_ractor.value rescue nil
    end

    def self.quit_requested?(ts)
      tuple = ts.read([:cmd, :quit]) rescue nil
      !tuple.nil?
    end
  end
end
```

The `quit_requested?` method needs a non-blocking peek. ts4r's `read` blocks. Workaround: keep a flag in the Dispatcher that observes `[:cmd, :quit]` writes, OR have the Dispatcher itself be quit-aware.

**Simplest:** the Dispatcher checks for `[:cmd, :quit]` between key reads. But `take([:cmd, :quit])` blocks too.

**Pragmatic fix:** the slash handler `:quit` writes both `[:cmd, :quit]` AND a sentinel `[:key, nil]` (EOF) to wake up the Input loop. The Dispatcher already returns `:quit` on `[:key, nil]`. So `ctx.quit` becomes:

```ruby
def quit
  @ts.write([:cmd, :quit])
  @ts.write([:key, nil])
end
```

Modify Context.quit accordingly. Tests for Context need to be updated to expect both tuples.

Update Task 6 retroactively in implementation: write a follow-up step here.

- [ ] **Step 4: Update `Cclikesh::Context#quit` to also write `[:key, nil]`**

Modify `lib/cclikesh/context.rb`:

```ruby
def quit
  @ts.write([:cmd, :quit])
  @ts.write([:key, nil])
end
```

- [ ] **Step 5: Update `test/test_context.rb` accordingly**

Replace the `test_quit_writes_cmd_quit_tuple` test with:

```ruby
def test_quit_writes_cmd_quit_and_eof_key
  ts = Cclikesh::TupleSpace.new
  c = Cclikesh::Context.new(ts)
  c.quit
  assert_equal [:cmd, :quit], ts.take([:cmd, :quit])
  assert_equal [:key, nil], ts.take([:key, nil])
end
```

- [ ] **Step 6: Simplify Runner — quit only via dispatcher returning `:quit`**

```ruby
# frozen_string_literal: true

require_relative "tuple_space"
require_relative "builder"
require_relative "context"
require_relative "dispatcher"
require_relative "render_ractor"
require_relative "input_ractor"

module Cclikesh
  class Runner
    def self.run(input_path:, output_path:, tick_interval: 0.06, &block)
      builder = Builder.new
      block.call(builder)

      ts = TupleSpace.new
      ctx = Context.new(ts)
      dispatcher = Dispatcher.new(ts, builder, ctx)

      render_ractor = RenderRactor.start(ts, output_path, tick_interval: tick_interval)
      InputRactor.start(ts, input_path)

      loop do
        break if dispatcher.dispatch_one == :quit
      end

      # Ensure quit signal is in the tuple space for RenderRactor's watcher
      ts.write([:cmd, :quit])
      render_ractor.value rescue nil
    end
  end
end
```

- [ ] **Step 7: Update `lib/cclikesh.rb` to expose `Cclikesh.run`**

```ruby
# frozen_string_literal: true

require_relative "cclikesh/version"
require_relative "cclikesh/runner"

module Cclikesh
  def self.run(input_path: $stdin, output_path: $stdout, tick_interval: 0.06, &block)
    Runner.run(input_path: input_path, output_path: output_path, tick_interval: tick_interval, &block)
  end
end
```

For Plan 1, defaults to stdin/stdout require special handling because `RenderRactor` opens the path with `File.open(output_path, "a")`. If `output_path` is `$stdout`, that fails. Plan 1 simplification: REQUIRE both as path strings; defaults raise. Document this limitation in the spec; Plan 2 (which introduces fork+dRuby and reline) replaces this with proper terminal handling.

```ruby
def self.run(input_path:, output_path:, tick_interval: 0.06, &block)
  Runner.run(input_path: input_path, output_path: output_path, tick_interval: tick_interval, &block)
end
```

- [ ] **Step 8: Run all tests, expect all PASS**

Run: `bundle exec rake test`
Expected: All tests pass. Output ends with `0 failures, 0 errors`.

- [ ] **Step 9: Commit**

```bash
git add lib/cclikesh/runner.rb lib/cclikesh.rb lib/cclikesh/context.rb test/test_runner.rb test/test_context.rb
git commit -m "feat: add Runner and Cclikesh.run end-to-end orchestration"
```

---

## Task 13: README + Verification

**Files:**
- Create: `README.md`
- Create: `examples/echo_shell.rb`
- Create: `LICENSE`

This task is documentation and a hand-runnable example. No new tests.

- [ ] **Step 1: Create `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 bash0C7

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Create `examples/echo_shell.rb`**

```ruby
# frozen_string_literal: true

require "cclikesh"

input_path = ARGV[0] || raise("usage: echo_shell.rb <input_path> <output_path>")
output_path = ARGV[1] || raise("usage: echo_shell.rb <input_path> <output_path>")

Cclikesh.run(input_path: input_path, output_path: output_path) do |shell|
  shell.on_submit do |line, ctx|
    ctx.display.append("you said: #{line}")
  end

  shell.slash(:quit) { |_args, ctx| ctx.quit }
end

puts "shell exited; output written to #{output_path}"
```

- [ ] **Step 3: Run the example end-to-end**

```bash
mkdir -p tmp
printf "hello world\n/quit\n" > tmp/input.txt
: > tmp/output.txt
bundle exec ruby -Ilib examples/echo_shell.rb tmp/input.txt tmp/output.txt
cat tmp/output.txt
```

Expected stdout from the example: `shell exited; output written to tmp/output.txt`
Expected `tmp/output.txt` contents: `you said: hello world\n`

- [ ] **Step 4: Create `README.md`**

```markdown
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
```

- [ ] **Step 5: Commit**

```bash
git add README.md LICENSE examples/echo_shell.rb
git commit -m "docs: add README, license, and echo_shell example"
```

---

## Self-Review Notes (already incorporated into the plan above)

- **Spec coverage:** Plan 1 covers spec sections 3.1 (entrypoint), 3.2 (Builder for on_submit + slash only), 3.3 (ctx.display.append + state[] + quit), 4.5 (quit path basics), 5.1+5.2 (display.append only — no live slot), 6.5 (slash dispatch only — no parsing edge cases). Sections 5.3 (live slot), 5.5 (styles), 6.1-6.4 (info bar), 6.5 (slash full parsing), 7.1 (state with on_state_change), 7.2 (full error handling), 7.3 (Ruby::Box), 7.4 (logger) are deferred to later plans (declared in "Out of scope").
- **Type consistency:** Tuple shapes are pinned: `[:key, line_or_nil]`, `[:render, :display_append, text, opts_hash]`, `[:event, :submit, line]`, `[:event, :slash, name_sym, args_array]`, `[:cmd, :quit]`, `[:state, key_sym, value]`, `[:event, :state_change, key, old, new]`, `[:rendered, frame_id]`. All tasks use these consistently.
- **Method names:** `dispatch_one`, `render_pending`, `read_one` are used as specified across tests and implementations.

## Future plans (not in scope here)

| # | Plan | Triggers |
|---|---|---|
| 2 | dRuby Split + reline | once Plan 1 echo shell is verified to work |
| 3 | Display Engine (live slot, dialog, styles) | builds on Plan 2 |
| 4 | Info Layer (spinner, segments, idle_phrases) | builds on Plan 2 |
| 5 | Command System (full slash, hooks, state) | builds on Plan 2 |
| 6 | Logger & Ruby::Box | independent of 3-5 once Plan 2 is in |
| 7 | Example irb_shell | requires plans 3-6 |

When ready to start Plan 2, invoke `superpowers:writing-plans` again referencing the design spec section 4.6 (Ractor + dRuby + ts4r) and section 7.3 (Ruby::Box).
