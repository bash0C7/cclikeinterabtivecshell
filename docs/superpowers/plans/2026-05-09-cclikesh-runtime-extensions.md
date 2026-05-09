# cclikesh — Runtime Extensions Implementation Plan (Plan 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add backend impl-facing API surface — state extensions, lifecycle hooks (on_start / on_quit / before_*/after_*), logger, on_tab + reline completion bridge, ctx.refresh — needed before the renderer overhaul (Plan 5) and irb capstone (Plan 6). No renderer-layout changes; this is pure backend wiring.

**Architecture:** State is already a DRb-fronted Hash (added in Plan 3 ahead of schedule); Plan 4 fills out `delete`/`update`/`to_h` and wires `on_state_change` consumption via a new `EventThread` that drains `[:event, :state_change, ...]` tuples and calls back to the impl-side `HandlerRegistry` over DRb. Lifecycle hooks (start/quit/before_submit/after_submit/before_tab/after_tab) wire through `Builder` registration → `HandlerRegistry` dispatch chain. Logger is a stdlib `Logger` instance held by the `Builder` and exposed as a DRb proxy via `Context#logger`. `on_tab` uses `Reline.completion_proc` to call `HandlerRegistry#dispatch_tab` over DRb. `ctx.refresh` writes `[:cmd, :refresh]` and the `RenderThread` replaces blind `sleep` with `ts.take([:cmd, :refresh], tick_interval)` for early wake-up. Task 1 also fixes the latent `retry_three_arg` ordering bug by padding `live_discard` to 4-arity.

**Tech Stack:** Ruby 4.0.3, dRuby (UNIX socket) + Rinda::TupleSpace, reline 0.5+, Ruby stdlib `Logger`, test-unit 3.6, single-commit-per-task discipline (English conventional commits).

**Position in roadmap:**
- Plan 4 (this): backend extensions
- Plan 5: 3-region renderer + info segments + spinner + idle_phrases + dialog primitive (rendering)
- Plan 6: irb_shell capstone (`IrbEvaluator` / `IrbCompleter` / `ByteCounter` + PTY E2E)

**Single-commit-per-task discipline:** Each task lands as ONE commit (test + impl + any wiring), not RED/GREEN/REFACTOR triplets. Conventional commit prefix in English. This overrides the global TDD commit boundary rule for this project.

---

### Task 1: Cleanup — pad `live_discard` tuple to 4-arity, delete `retry_three_arg`

**Files:**
- Modify: `lib/cclikesh/live_slot.rb`
- Modify: `lib/cclikesh/renderer.rb`
- Test: `test/test_live_slot.rb`, `test/test_renderer.rb`

**Why:** Plan 3 final reviewer flagged `retry_three_arg` as a latent ordering bug (separate drain pass for 3-arity tuples loses interleaving with 4-arity tuples within one tick). Currently dormant because `LiveSlot` state machine prevents problematic interleavings, but Plan 5 will introduce more tuple kinds (`info`, `spinner_label`, `dialog`) so we want a single 4-arity drain model before that.

- [ ] **Step 1:** Update `LiveSlot#discard` to write 4-arity tuple

```ruby
# lib/cclikesh/live_slot.rb — change inside #discard:
def discard
  @mutex.synchronize do
    return unless @state == :open
    @state = :discarded
    @ts.write([:render, :live_discard, @id, nil])  # was 3-arity, now 4-arity
  end
end
```

- [ ] **Step 2:** Update `Renderer#process_live_discard` to destructure 4-arity

```ruby
# lib/cclikesh/renderer.rb — replace existing #process_live_discard:
def process_live_discard(tuple)
  _, _, id, _ = tuple
  return unless @live_state && @live_state[:id] == id
  @out.write("\r\e[2K")
  @live_state = nil
end
```

- [ ] **Step 3:** Delete `Renderer#retry_three_arg` and its call site in `#render_pending`

```ruby
# lib/cclikesh/renderer.rb — replace #render_pending:
def render_pending
  collected = []
  loop do
    collected << @ts.take([:render, nil, nil, nil], 0)
  end
rescue Rinda::RequestExpiredError
  collected.reverse_each { |t| process(t) }
end
# Delete the private #retry_three_arg method entirely (and its preceding comment).
```

- [ ] **Step 4:** Update `test/test_live_slot.rb` to expect 4-arity discard tuple

Find any test that asserts `[:render, :live_discard, id]` and update to `[:render, :live_discard, id, nil]`. Search:
```
grep -n live_discard test/test_live_slot.rb test/test_renderer.rb
```

- [ ] **Step 5:** Run tests

```
bundle exec rake test
```
Expected: 89 tests, 0 failures (no new tests, behavior unchanged).

- [ ] **Step 6:** Commit

```bash
git add lib/cclikesh/live_slot.rb lib/cclikesh/renderer.rb test/test_live_slot.rb test/test_renderer.rb
git commit -m "refactor: unify live_discard tuple to 4-arity, drop retry_three_arg"
```

---

### Task 2: Logger — `Builder.logger` / `log_level=` / `log_to`

**Files:**
- Modify: `lib/cclikesh/builder.rb`
- Test: `test/test_builder.rb`

**Why:** spec §3.2 / §7.4 says core ships a stdlib `Logger`-compatible instance. Default `$stderr`, level `:info`, progname `"cclikesh"`. Builder owns the config so it can be set in the registration block.

- [ ] **Step 1:** Add failing test in `test/test_builder.rb`

```ruby
def test_logger_defaults_to_info_level_stderr_progname
  builder = Cclikesh::Builder.new
  logger = builder.logger
  assert_kind_of Logger, logger
  assert_equal Logger::INFO, logger.level
  assert_equal "cclikesh", logger.progname
end

def test_log_level_setter_accepts_symbols
  builder = Cclikesh::Builder.new
  builder.log_level = :debug
  assert_equal Logger::DEBUG, builder.logger.level
  builder.log_level = :warn
  assert_equal Logger::WARN, builder.logger.level
end

def test_log_to_redirects_output
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  builder.logger.info("hello")
  assert_match(/hello/, io.string)
end
```

Add `require "logger"` and `require "stringio"` at top of `test/test_builder.rb` if not present.

- [ ] **Step 2:** Run — expect FAIL (no `#logger`).

```
bundle exec rake test TEST=test/test_builder.rb
```

- [ ] **Step 3:** Implement in `lib/cclikesh/builder.rb`

```ruby
require "logger"

module Cclikesh
  class Builder
    LOG_LEVELS = {
      debug: Logger::DEBUG, info: Logger::INFO,
      warn: Logger::WARN, error: Logger::ERROR, fatal: Logger::FATAL
    }.freeze

    attr_reader :on_submit_handler, :slash_handlers, :logger

    def initialize
      @on_submit_handler = nil
      @slash_handlers = {}
      @styles = {}
      @logger = Logger.new($stderr)
      @logger.level = Logger::INFO
      @logger.progname = "cclikesh"
    end

    # ... existing on_submit / slash / slash_handler / define_style / style_definition ...

    def logger=(other)
      @logger = other
    end

    def log_level=(sym)
      level = LOG_LEVELS[sym.to_sym]
      raise ArgumentError, "unknown log level: #{sym.inspect}" unless level
      @logger.level = level
    end

    def log_to(target)
      @logger = case target
                when IO, StringIO then Logger.new(target)
                when String       then Logger.new(target)
                else raise ArgumentError, "log_to expects IO or path String, got #{target.class}"
                end
      @logger.level = Logger::INFO
      @logger.progname = "cclikesh"
    end
  end
end
```

- [ ] **Step 4:** Run — expect PASS

```
bundle exec rake test TEST=test/test_builder.rb
```

- [ ] **Step 5:** Commit

```bash
git add lib/cclikesh/builder.rb test/test_builder.rb
git commit -m "feat: add Builder logger config (logger / log_level= / log_to)"
```

---

### Task 3: `ctx.logger` DRb proxy

**Files:**
- Modify: `lib/cclikesh/handler_registry.rb`
- Modify: `lib/cclikesh/context.rb`
- Test: `test/test_handler_registry.rb`, `test/test_context.rb`

**Why:** spec §3.3 `ctx.logger.debug/info/warn/error/fatal(...)` — impl needs to log via the Builder-configured logger over DRb.

- [ ] **Step 1:** Failing test in `test/test_handler_registry.rb`

```ruby
def test_registry_exposes_builder_logger
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  builder.log_level = :debug
  registry = Cclikesh::HandlerRegistry.new(builder)

  registry.logger.info("from-impl")
  assert_match(/from-impl/, io.string)
end
```

Add `require "stringio"` if not present.

- [ ] **Step 2:** Failing test in `test/test_context.rb`

```ruby
def test_context_logger_returns_registry_logger
  ts = Cclikesh::TupleSpace.new
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  registry = Cclikesh::HandlerRegistry.new(builder)
  ctx = Cclikesh::Context.new(ts, registry: registry)

  ctx.logger.info("through-ctx")
  assert_match(/through-ctx/, io.string)
end
```

- [ ] **Step 3:** Run — expect FAIL.

- [ ] **Step 4:** Add `HandlerRegistry#logger`

```ruby
# lib/cclikesh/handler_registry.rb — add:
def logger
  @builder.logger
end
```

- [ ] **Step 5:** Modify `Cclikesh::Context` to accept `registry:` and expose `#logger`

```ruby
# lib/cclikesh/context.rb
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

    def logger
      @registry&.logger
    end

    def quit
      @ts.write([:cmd, :quit])
      @ts.write([:key, nil])
    end
  end
end
```

- [ ] **Step 6:** Update `Runner.run_child` to pass `registry:` to Context

```ruby
# lib/cclikesh/runner.rb — change inside run_child:
ctx = Context.new(ts, registry: registry_remote)
```

- [ ] **Step 7:** Run all tests — expect PASS

```
bundle exec rake test
```

- [ ] **Step 8:** Commit

```bash
git add lib/cclikesh/handler_registry.rb lib/cclikesh/context.rb lib/cclikesh/runner.rb test/test_handler_registry.rb test/test_context.rb
git commit -m "feat: expose ctx.logger via HandlerRegistry DRb proxy"
```

---

### Task 4: `State#delete` / `#update` / `#to_h`

**Files:**
- Modify: `lib/cclikesh/state.rb`
- Test: `test/test_state.rb`

**Why:** spec §3.3 lists these three. Each mutation path must also fire `[:event, :state_change, key, old, new]` like `[]=` does (delete = new is `nil`, update = batch).

- [ ] **Step 1:** Failing tests in `test/test_state.rb`

```ruby
def test_delete_removes_key_and_emits_state_change
  ts = Cclikesh::TupleSpace.new
  state = Cclikesh::State.new(ts)
  state[:phase] = :working
  drain_state_change_tuples(ts)  # see helper below

  state.delete(:phase)
  assert_nil state[:phase]
  _, _, key, old, new = ts.take([:event, :state_change, nil, nil, nil], 1)
  assert_equal :phase, key
  assert_equal :working, old
  assert_nil new
end

def test_delete_missing_key_is_noop
  ts = Cclikesh::TupleSpace.new
  state = Cclikesh::State.new(ts)
  state.delete(:never_set)
  assert_raise(Rinda::RequestExpiredError) do
    ts.take([:event, :state_change, nil, nil, nil], 0)
  end
end

def test_update_writes_each_changed_pair
  ts = Cclikesh::TupleSpace.new
  state = Cclikesh::State.new(ts)
  state.update(a: 1, b: 2)
  assert_equal 1, state[:a]
  assert_equal 2, state[:b]
end

def test_to_h_returns_snapshot
  ts = Cclikesh::TupleSpace.new
  state = Cclikesh::State.new(ts)
  state[:a] = 1
  state[:b] = "two"
  assert_equal({ a: 1, b: "two" }, state.to_h)
end

private

def drain_state_change_tuples(ts)
  loop { ts.take([:event, :state_change, nil, nil, nil], 0) }
rescue Rinda::RequestExpiredError
  # done
end
```

- [ ] **Step 2:** Run — expect FAIL.

- [ ] **Step 3:** Implement in `lib/cclikesh/state.rb`

```ruby
require "drb/drb"

module Cclikesh
  class State
    include DRb::DRbUndumped

    def initialize(tuple_space)
      @ts = tuple_space
      @cache = {}
      @mutex = Mutex.new
    end

    def [](key)
      @mutex.synchronize { @cache[key.to_sym] }
    end

    def []=(key, value)
      sym = key.to_sym
      old, changed = @mutex.synchronize do
        prev = @cache[sym]
        @cache[sym] = value
        [prev, prev != value]
      end
      @ts.write([:state, sym, value])
      @ts.write([:event, :state_change, sym, old, value]) if changed
    end

    def delete(key)
      sym = key.to_sym
      old, existed = @mutex.synchronize do
        had = @cache.key?(sym)
        prev = @cache.delete(sym)
        [prev, had]
      end
      return nil unless existed
      @ts.write([:event, :state_change, sym, old, nil])
      old
    end

    def update(hash)
      hash.each { |k, v| self[k] = v }
      self
    end

    def to_h
      @mutex.synchronize { @cache.dup }
    end
  end
end
```

- [ ] **Step 4:** Run all tests — expect PASS.

- [ ] **Step 5:** Commit

```bash
git add lib/cclikesh/state.rb test/test_state.rb
git commit -m "feat: add State#delete / #update / #to_h with state_change events"
```

---

### Task 5: `on_state_change` wire — Builder + Registry + EventThread + Runner

**Files:**
- Create: `lib/cclikesh/event_thread.rb`
- Modify: `lib/cclikesh/builder.rb`
- Modify: `lib/cclikesh/handler_registry.rb`
- Modify: `lib/cclikesh/runner.rb`
- Modify: `lib/cclikesh.rb` (autoload)
- Test: `test/test_event_thread.rb` (new), `test/test_builder.rb`, `test/test_handler_registry.rb`

**Why:** spec §3.2 — impl can register one block fired with `(key, old, new, ctx)` whenever state changes. State already writes the tuple; we need a consumer thread in F that drains `[:event, :state_change, ...]` and calls `registry.dispatch_state_change` over DRb.

- [ ] **Step 1:** Failing test in `test/test_builder.rb`

```ruby
def test_on_state_change_registers_block
  builder = Cclikesh::Builder.new
  called = []
  builder.on_state_change { |k, o, n, _ctx| called << [k, o, n] }
  builder.on_state_change_handler.call(:phase, nil, :working, nil)
  assert_equal [[:phase, nil, :working]], called
end
```

- [ ] **Step 2:** Add `Builder#on_state_change`

```ruby
# lib/cclikesh/builder.rb — add attr & method:
attr_reader :on_state_change_handler  # add to existing attr_reader line

def initialize
  # ... existing
  @on_state_change_handler = nil
end

def on_state_change(&block)
  @on_state_change_handler = block
end
```

- [ ] **Step 3:** Failing test in `test/test_handler_registry.rb`

```ruby
def test_dispatch_state_change_calls_handler
  builder = Cclikesh::Builder.new
  recorded = []
  builder.on_state_change { |k, o, n, ctx| recorded << [k, o, n, ctx] }
  registry = Cclikesh::HandlerRegistry.new(builder)
  registry.dispatch_state_change(:phase, nil, :working, :ctx_sentinel)
  assert_equal [[:phase, nil, :working, :ctx_sentinel]], recorded
end

def test_dispatch_state_change_no_handler_is_noop
  builder = Cclikesh::Builder.new
  registry = Cclikesh::HandlerRegistry.new(builder)
  assert_nothing_raised do
    registry.dispatch_state_change(:phase, nil, :working, :ctx)
  end
end
```

- [ ] **Step 4:** Add `HandlerRegistry#dispatch_state_change`

```ruby
# lib/cclikesh/handler_registry.rb — add:
def dispatch_state_change(key, old, new, ctx)
  handler = @builder.on_state_change_handler
  handler.call(key, old, new, ctx) if handler
  nil
rescue => e
  logger.error("on_state_change error: #{e.full_message}")
  nil
end
```

- [ ] **Step 5:** Failing test in `test/test_event_thread.rb` (new file)

```ruby
require_relative "test_helper"
require "cclikesh/event_thread"
require "cclikesh/tuple_space"

class TestEventThread < Test::Unit::TestCase
  def test_drains_state_change_and_calls_dispatch_state_change
    ts = Cclikesh::TupleSpace.new
    fake = []
    fake_registry = Object.new
    fake_registry.define_singleton_method(:dispatch_state_change) do |k, o, n, c|
      fake << [k, o, n, c]
    end

    thread = Cclikesh::EventThread.start(ts, registry: fake_registry, ctx: :ctx_sentinel)

    ts.write([:event, :state_change, :phase, nil, :working])

    deadline = Time.now + 1
    sleep 0.01 until !fake.empty? || Time.now > deadline

    ts.write([:cmd, :quit])
    thread.join(2)

    assert_equal [[:phase, nil, :working, :ctx_sentinel]], fake
  end
end
```

- [ ] **Step 6:** Implement `lib/cclikesh/event_thread.rb`

```ruby
# frozen_string_literal: true

require "rinda/tuplespace"

module Cclikesh
  class EventThread
    def self.start(ts, registry:, ctx:)
      Thread.new do
        loop do
          quit_tuple = begin
            ts.read([:cmd, :quit], 0)
          rescue Rinda::RequestExpiredError
            nil
          end
          break if quit_tuple

          begin
            _, _, key, old, new_v = ts.take([:event, :state_change, nil, nil, nil], 0.05)
            registry.dispatch_state_change(key, old, new_v, ctx)
          rescue Rinda::RequestExpiredError
            # tick
          end
        end
      end
    end
  end
end
```

- [ ] **Step 7:** Wire into `Runner.run_child`

```ruby
# lib/cclikesh/runner.rb — add require and start EventThread before main loop:
require_relative "event_thread"

# ... in run_child, after RenderThread.start and InputThread.start:
event_thread = EventThread.start(ts, registry: registry_remote, ctx: ctx)

# in shutdown sequence:
event_thread.join(2)
```

- [ ] **Step 8:** Add autoload entry in `lib/cclikesh.rb`

```ruby
# lib/cclikesh.rb — add (alongside existing autoloads):
autoload :EventThread, "cclikesh/event_thread"
```

- [ ] **Step 9:** Run all tests — expect PASS.

- [ ] **Step 10:** Commit

```bash
git add lib/cclikesh/builder.rb lib/cclikesh/handler_registry.rb lib/cclikesh/event_thread.rb lib/cclikesh/runner.rb lib/cclikesh.rb test/test_builder.rb test/test_handler_registry.rb test/test_event_thread.rb
git commit -m "feat: dispatch on_state_change via dedicated EventThread"
```

---

### Task 6: `on_start` hook (multiple registration, fired before main loop)

**Files:**
- Modify: `lib/cclikesh/builder.rb`
- Modify: `lib/cclikesh/handler_registry.rb`
- Modify: `lib/cclikesh/runner.rb`
- Test: `test/test_builder.rb`, `test/test_handler_registry.rb`

**Why:** spec §3.2 — `on_start(ctx)`, multiple registration, fires once after F is up.

- [ ] **Step 1:** Failing test in `test/test_builder.rb`

```ruby
def test_on_start_collects_multiple_handlers_in_registration_order
  builder = Cclikesh::Builder.new
  builder.on_start { |_| 1 }
  builder.on_start { |_| 2 }
  assert_equal 2, builder.on_start_handlers.size
end
```

- [ ] **Step 2:** Failing test in `test/test_handler_registry.rb`

```ruby
def test_dispatch_start_runs_each_in_registration_order
  builder = Cclikesh::Builder.new
  seq = []
  builder.on_start { |_| seq << :first }
  builder.on_start { |_| seq << :second }
  registry = Cclikesh::HandlerRegistry.new(builder)
  registry.dispatch_start(:ctx)
  assert_equal [:first, :second], seq
end

def test_dispatch_start_logs_and_continues_on_error
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  seq = []
  builder.on_start { |_| raise "boom" }
  builder.on_start { |_| seq << :ran }
  registry = Cclikesh::HandlerRegistry.new(builder)
  registry.dispatch_start(:ctx)
  assert_equal [:ran], seq
  assert_match(/boom/, io.string)
end
```

- [ ] **Step 3:** Implement in `Builder`

```ruby
# lib/cclikesh/builder.rb
attr_reader :on_start_handlers  # add to attr_reader

def initialize
  # ... existing
  @on_start_handlers = []
end

def on_start(&block)
  @on_start_handlers << block
end
```

- [ ] **Step 4:** Implement in `HandlerRegistry`

```ruby
# lib/cclikesh/handler_registry.rb
def dispatch_start(ctx)
  @builder.on_start_handlers.each do |h|
    begin
      h.call(ctx)
    rescue => e
      logger.error("on_start error: #{e.full_message}")
    end
  end
  nil
end
```

- [ ] **Step 5:** Wire into `Runner.run_child`

```ruby
# lib/cclikesh/runner.rb — call after threads started, before main loop:
registry_remote.dispatch_start(ctx)

loop do
  break if dispatcher.dispatch_one == :quit
end
```

- [ ] **Step 6:** Run all tests — expect PASS.

- [ ] **Step 7:** Commit

```bash
git add lib/cclikesh/builder.rb lib/cclikesh/handler_registry.rb lib/cclikesh/runner.rb test/test_builder.rb test/test_handler_registry.rb
git commit -m "feat: add on_start lifecycle hook"
```

---

### Task 7: `on_quit` hook (multiple registration, fired in REVERSE order at shutdown)

**Files:**
- Modify: `lib/cclikesh/builder.rb`
- Modify: `lib/cclikesh/handler_registry.rb`
- Modify: `lib/cclikesh/runner.rb`
- Test: `test/test_builder.rb`, `test/test_handler_registry.rb`

**Why:** spec §3.2 — `on_quit(ctx)`, multiple, REVERSE order on shutdown so teardown unwinds setup.

- [ ] **Step 1:** Failing tests

```ruby
# test/test_builder.rb
def test_on_quit_collects_handlers
  builder = Cclikesh::Builder.new
  builder.on_quit { |_| 1 }
  builder.on_quit { |_| 2 }
  assert_equal 2, builder.on_quit_handlers.size
end

# test/test_handler_registry.rb
def test_dispatch_quit_runs_in_reverse_order
  builder = Cclikesh::Builder.new
  seq = []
  builder.on_quit { |_| seq << :first }
  builder.on_quit { |_| seq << :second }
  registry = Cclikesh::HandlerRegistry.new(builder)
  registry.dispatch_quit(:ctx)
  assert_equal [:second, :first], seq
end
```

- [ ] **Step 2:** Implement in `Builder`

```ruby
# add attr_reader :on_quit_handlers; @on_quit_handlers = []
def on_quit(&block)
  @on_quit_handlers << block
end
```

- [ ] **Step 3:** Implement in `HandlerRegistry`

```ruby
def dispatch_quit(ctx)
  @builder.on_quit_handlers.reverse_each do |h|
    begin
      h.call(ctx)
    rescue => e
      logger.error("on_quit error: #{e.full_message}")
    end
  end
  nil
end
```

- [ ] **Step 4:** Wire into `Runner.run_child` shutdown sequence

```ruby
# lib/cclikesh/runner.rb — after main loop break, before ts.write([:cmd, :quit]):
registry_remote.dispatch_quit(ctx)

ts.write([:cmd, :quit])
```

- [ ] **Step 5:** Run tests — expect PASS.

- [ ] **Step 6:** Commit

```bash
git add lib/cclikesh/builder.rb lib/cclikesh/handler_registry.rb lib/cclikesh/runner.rb test/test_builder.rb test/test_handler_registry.rb
git commit -m "feat: add on_quit lifecycle hook (reverse order at shutdown)"
```

---

### Task 8: `before_submit` / `after_submit` hooks

**Files:**
- Modify: `lib/cclikesh/builder.rb`
- Modify: `lib/cclikesh/handler_registry.rb`
- Test: `test/test_builder.rb`, `test/test_handler_registry.rb`

**Why:** spec §3.2 — `(line, ctx)` blocks before & after `on_submit`. Per §7.2: hook exception → error log → chain abort → main `on_submit` continues.

- [ ] **Step 1:** Failing test in `test/test_handler_registry.rb`

```ruby
def test_dispatch_submit_runs_before_main_after_in_order
  builder = Cclikesh::Builder.new
  seq = []
  builder.before_submit { |line, _ctx| seq << [:before, line] }
  builder.on_submit     { |line, _ctx| seq << [:main,   line] }
  builder.after_submit  { |line, _ctx| seq << [:after,  line] }
  registry = Cclikesh::HandlerRegistry.new(builder)
  registry.dispatch_submit("hi", :ctx)
  assert_equal [[:before, "hi"], [:main, "hi"], [:after, "hi"]], seq
end

def test_before_submit_exception_aborts_chain_main_continues
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  seq = []
  builder.before_submit { |_, _| seq << :before_a; raise "boom" }
  builder.before_submit { |_, _| seq << :before_b }
  builder.on_submit     { |_, _| seq << :main }
  builder.after_submit  { |_, _| seq << :after }
  registry = Cclikesh::HandlerRegistry.new(builder)
  registry.dispatch_submit("hi", :ctx)
  assert_equal [:before_a, :main, :after], seq
  assert_match(/boom/, io.string)
end

def test_main_submit_exception_logged_does_not_break_loop
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  builder.on_submit { |_, _| raise "main-boom" }
  registry = Cclikesh::HandlerRegistry.new(builder)
  assert_nothing_raised { registry.dispatch_submit("hi", :ctx) }
  assert_match(/main-boom/, io.string)
end
```

- [ ] **Step 2:** Implement in `Builder`

```ruby
# add attr_readers :before_submit_handlers, :after_submit_handlers
# init both as []
def before_submit(&block); @before_submit_handlers << block; end
def after_submit(&block);  @after_submit_handlers  << block; end
```

- [ ] **Step 3:** Replace `HandlerRegistry#dispatch_submit`

```ruby
def dispatch_submit(line, ctx)
  @builder.before_submit_handlers.each do |h|
    begin
      h.call(line, ctx)
    rescue => e
      logger.error("before_submit error: #{e.full_message}")
      break
    end
  end

  main = @builder.on_submit_handler
  if main
    begin
      main.call(line, ctx)
    rescue => e
      logger.error("on_submit error: #{e.full_message}")
    end
  end

  @builder.after_submit_handlers.each do |h|
    begin
      h.call(line, ctx)
    rescue => e
      logger.error("after_submit error: #{e.full_message}")
      break
    end
  end
  nil
end
```

- [ ] **Step 4:** Run tests — expect PASS.

- [ ] **Step 5:** Commit

```bash
git add lib/cclikesh/builder.rb lib/cclikesh/handler_registry.rb test/test_builder.rb test/test_handler_registry.rb
git commit -m "feat: add before_submit / after_submit hooks with error isolation"
```

---

### Task 9: `on_tab` dispatch + Reline `completion_proc` bridge

**Files:**
- Modify: `lib/cclikesh/builder.rb`
- Modify: `lib/cclikesh/handler_registry.rb`
- Modify: `lib/cclikesh/input_thread.rb`
- Modify: `lib/cclikesh/runner.rb`
- Test: `test/test_builder.rb`, `test/test_handler_registry.rb`, `test/test_input_thread.rb`

**Why:** spec §3.2 / §4.3 — `on_tab(buf, pos, ctx)` returns candidate array. Reline's `completion_proc` is the bridge: when user presses Tab, Reline calls our proc with the buffer text, we forward to impl over DRb, and return candidates back to Reline for display.

- [ ] **Step 1:** Failing test in `test/test_handler_registry.rb`

```ruby
def test_dispatch_tab_returns_candidates_from_handler
  builder = Cclikesh::Builder.new
  builder.on_tab { |buf, pos, _ctx| ["#{buf}_a", "#{buf}_b"] + [pos.to_s] }
  registry = Cclikesh::HandlerRegistry.new(builder)
  result = registry.dispatch_tab("foo", 3, :ctx)
  assert_equal ["foo_a", "foo_b", "3"], result
end

def test_dispatch_tab_no_handler_returns_empty
  builder = Cclikesh::Builder.new
  registry = Cclikesh::HandlerRegistry.new(builder)
  assert_equal [], registry.dispatch_tab("buf", 0, :ctx)
end

def test_dispatch_tab_exception_logs_and_returns_empty
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  builder.on_tab { |_, _, _| raise "tab-boom" }
  registry = Cclikesh::HandlerRegistry.new(builder)
  assert_equal [], registry.dispatch_tab("buf", 0, :ctx)
  assert_match(/tab-boom/, io.string)
end
```

- [ ] **Step 2:** Failing test in `test/test_builder.rb`

```ruby
def test_on_tab_registers_block
  builder = Cclikesh::Builder.new
  builder.on_tab { |buf, pos, _| [buf, pos] }
  assert_equal ["x", 1], builder.on_tab_handler.call("x", 1, nil)
end
```

- [ ] **Step 3:** Implement Builder + Registry

```ruby
# lib/cclikesh/builder.rb
attr_reader :on_tab_handler  # add
# init @on_tab_handler = nil
def on_tab(&block); @on_tab_handler = block; end

# lib/cclikesh/handler_registry.rb
def dispatch_tab(buf, pos, ctx)
  handler = @builder.on_tab_handler
  return [] unless handler
  result = handler.call(buf, pos, ctx)
  result.is_a?(Array) ? result : []
rescue => e
  logger.error("on_tab error: #{e.full_message}")
  []
end
```

- [ ] **Step 4:** Failing test in `test/test_input_thread.rb`

```ruby
def test_completion_proc_forwards_to_registry_dispatch_tab
  ts = Cclikesh::TupleSpace.new
  fake_registry = Object.new
  recorded = []
  fake_registry.define_singleton_method(:dispatch_tab) do |buf, pos, ctx|
    recorded << [buf, pos, ctx]
    ["alpha", "beta"]
  end

  ctx_sentinel = :ctx_x
  proc_returned = nil
  Cclikesh::InputThread.install_completion_proc(
    registry: fake_registry, ctx: ctx_sentinel,
    apply: ->(p) { proc_returned = p }
  )
  candidates = proc_returned.call("foo")
  assert_equal ["alpha", "beta"], candidates
  assert_equal [["foo", 3, :ctx_x]], recorded
end
```

(Note: `install_completion_proc` lets us test the wiring without touching real Reline.)

- [ ] **Step 5:** Add `InputThread.install_completion_proc` and call it from `.start`

```ruby
# lib/cclikesh/input_thread.rb
require "reline"

module Cclikesh
  class InputThread
    def self.install_completion_proc(registry:, ctx:, apply: ->(p) { Reline.completion_proc = p })
      proc = ->(buf) {
        registry.dispatch_tab(buf, buf.bytesize, ctx)
      }
      apply.call(proc)
      proc
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

          line = reader.call(prompt)
          payload = line.nil? ? nil : line.chomp
          ts.write([:key, payload])
          break if payload.nil?
        end
      end
    end
  end
end
```

- [ ] **Step 6:** Pass `registry:` and `ctx:` from `Runner.run_child` to `InputThread.start`

```ruby
# lib/cclikesh/runner.rb — change input_thread setup:
input_thread = InputThread.start(
  ts, reader: Reline.method(:readline), prompt: "> ",
  registry: registry_remote, ctx: ctx
)
```

- [ ] **Step 7:** Run all tests — expect PASS.

- [ ] **Step 8:** Commit

```bash
git add lib/cclikesh/builder.rb lib/cclikesh/handler_registry.rb lib/cclikesh/input_thread.rb lib/cclikesh/runner.rb test/test_builder.rb test/test_handler_registry.rb test/test_input_thread.rb
git commit -m "feat: dispatch on_tab via Reline completion_proc bridge"
```

---

### Task 10: `before_tab` / `after_tab` hooks

**Files:**
- Modify: `lib/cclikesh/builder.rb`
- Modify: `lib/cclikesh/handler_registry.rb`
- Test: `test/test_builder.rb`, `test/test_handler_registry.rb`

**Why:** spec §3.2 — `before_tab(buf, pos, ctx)` and `after_tab(buf, pos, candidates, ctx)`. before runs in registration order. after gets the resolved candidates and runs after impl returns. Hook exceptions abort the chain but the main on_tab still runs.

- [ ] **Step 1:** Failing tests

```ruby
# test/test_handler_registry.rb
def test_dispatch_tab_runs_before_main_after
  builder = Cclikesh::Builder.new
  seq = []
  builder.before_tab { |b, p, _|       seq << [:before, b, p] }
  builder.on_tab     { |b, p, _|       seq << [:main,   b, p]; ["x", "y"] }
  builder.after_tab  { |b, p, c, _|    seq << [:after,  b, p, c] }
  registry = Cclikesh::HandlerRegistry.new(builder)
  result = registry.dispatch_tab("foo", 3, :ctx)
  assert_equal ["x", "y"], result
  assert_equal(
    [[:before, "foo", 3], [:main, "foo", 3], [:after, "foo", 3, ["x", "y"]]],
    seq
  )
end

def test_before_tab_exception_does_not_break_dispatch
  io = StringIO.new
  builder = Cclikesh::Builder.new
  builder.log_to(io)
  builder.before_tab { |_, _, _| raise "tab-before-boom" }
  builder.on_tab     { |_, _, _| ["x"] }
  registry = Cclikesh::HandlerRegistry.new(builder)
  result = registry.dispatch_tab("foo", 0, :ctx)
  assert_equal ["x"], result
  assert_match(/tab-before-boom/, io.string)
end
```

- [ ] **Step 2:** Implement Builder

```ruby
# attr_readers :before_tab_handlers, :after_tab_handlers; init []
def before_tab(&block); @before_tab_handlers << block; end
def after_tab(&block);  @after_tab_handlers  << block; end
```

- [ ] **Step 3:** Replace `HandlerRegistry#dispatch_tab`

```ruby
def dispatch_tab(buf, pos, ctx)
  @builder.before_tab_handlers.each do |h|
    begin
      h.call(buf, pos, ctx)
    rescue => e
      logger.error("before_tab error: #{e.full_message}")
      break
    end
  end

  candidates = []
  if (handler = @builder.on_tab_handler)
    begin
      result = handler.call(buf, pos, ctx)
      candidates = result.is_a?(Array) ? result : []
    rescue => e
      logger.error("on_tab error: #{e.full_message}")
    end
  end

  @builder.after_tab_handlers.each do |h|
    begin
      h.call(buf, pos, candidates, ctx)
    rescue => e
      logger.error("after_tab error: #{e.full_message}")
      break
    end
  end

  candidates
end
```

- [ ] **Step 4:** Run tests — expect PASS.

- [ ] **Step 5:** Commit

```bash
git add lib/cclikesh/builder.rb lib/cclikesh/handler_registry.rb test/test_builder.rb test/test_handler_registry.rb
git commit -m "feat: add before_tab / after_tab hooks with candidate flow"
```

---

### Task 11: `ctx.refresh` + `RenderThread` refresh-aware sleep

**Files:**
- Modify: `lib/cclikesh/context.rb`
- Modify: `lib/cclikesh/render_thread.rb`
- Test: `test/test_context.rb`, `test/test_render_thread.rb`

**Why:** spec §4.2 — `ctx.refresh` should make Render R wake immediately for the next tick rather than waiting for the timer. Replace blind `sleep tick_interval` with `ts.take([:cmd, :refresh], tick_interval)` so a written `[:cmd, :refresh]` tuple short-circuits the sleep.

- [ ] **Step 1:** Failing test in `test/test_context.rb`

```ruby
def test_refresh_writes_refresh_command_tuple
  ts = Cclikesh::TupleSpace.new
  ctx = Cclikesh::Context.new(ts)
  ctx.refresh
  tuple = ts.take([:cmd, :refresh], 1)
  assert_equal [:cmd, :refresh], tuple
end
```

- [ ] **Step 2:** Failing test in `test/test_render_thread.rb`

```ruby
def test_refresh_signal_short_circuits_sleep
  ts = Cclikesh::TupleSpace.new
  io = StringIO.new
  thread = Cclikesh::RenderThread.start(ts, io, tick_interval: 5.0)

  start = Time.now
  ts.write([:render, :display_append, "fast", {}])
  ts.write([:cmd, :refresh])

  deadline = Time.now + 2
  sleep 0.02 until io.string.include?("fast") || Time.now > deadline
  elapsed = Time.now - start

  ts.write([:cmd, :quit])
  thread.join(2)

  assert_match(/fast/, io.string)
  assert(elapsed < 1.5, "expected refresh to short-circuit 5s tick (got #{elapsed}s)")
end
```

- [ ] **Step 3:** Implement `Context#refresh`

```ruby
# lib/cclikesh/context.rb — add:
def refresh
  @ts.write([:cmd, :refresh])
end
```

- [ ] **Step 4:** Implement refresh-aware sleep in `RenderThread`

```ruby
# lib/cclikesh/render_thread.rb
require_relative "renderer"
require "rinda/tuplespace"

module Cclikesh
  class RenderThread
    def self.start(ts, output_io, tick_interval: 0.06, registry: nil)
      Thread.new do
        renderer = Renderer.new(ts, output_io, registry: registry)
        stopping = false
        watcher = Thread.new do
          ts.read([:cmd, :quit])
          stopping = true
        end
        until stopping
          begin
            ts.take([:cmd, :refresh], tick_interval)
          rescue Rinda::RequestExpiredError
            # normal tick
          end
          renderer.render_pending
          output_io.flush
        end
        renderer.render_pending
        output_io.flush
        watcher.kill
      end
    end
  end
end
```

- [ ] **Step 5:** Run all tests — expect PASS.

- [ ] **Step 6:** Commit

```bash
git add lib/cclikesh/context.rb lib/cclikesh/render_thread.rb test/test_context.rb test/test_render_thread.rb
git commit -m "feat: add ctx.refresh signal with refresh-aware render tick"
```

---

## Self-Review Checklist (controller fills in before dispatch)

- **Spec coverage:** §3.2 (Builder hooks), §3.3 (ctx.logger / ctx.refresh), §4.5 (quit hooks), §7.1 (state delete/update/to_h), §7.2 (callback rescue → logger), §7.4 (logger defaults). dialog / info / spinner / idle_phrases / spinner_label / tick_interval setting / define_style remain → Plan 5. ✅
- **Placeholder scan:** No TBD/TODO. Every step has concrete code or exact command. ✅
- **Type consistency:** `dispatch_state_change(key, old, new, ctx)` matches everywhere; `dispatch_tab(buf, pos, ctx) → Array` matches Reline expectation; `EventThread.start(ts, registry:, ctx:)` keyword sig consistent. ✅
- **Single-commit-per-task:** All 11 tasks land as 1 commit each (test + impl together) per project's per-task discipline override. ✅

---

## After Plan 4

Plan 5 (rendering: 3-region + info + spinner + idle + dialog) and Plan 6 (irb capstone) remain. Plan 4 leaves `Cclikesh.run do |shell| ... end` with full backend API — impl can register all hooks, mutate state, log, refresh, complete on tab — but the visual layout is still Plan 3-style (history-only display + reline input below). Plan 5 transforms the renderer into 3-region. Plan 6 ships `examples/irb_shell/` end-to-end with PTY E2E.
