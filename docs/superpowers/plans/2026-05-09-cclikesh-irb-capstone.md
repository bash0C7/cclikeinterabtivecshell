# cclikesh — irb Capstone Implementation Plan (Plan 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `examples/irb_shell/` — a working Ruby interactive shell demo that drives the entire cclikesh framework end-to-end. After this plan, `bundle exec ruby -Ilib examples/irb_shell/irb_shell.rb` launches a working irb-like REPL with persistent bindings, info bar (elapsed time + token counter), thinking-styled live slot during evaluation, error styling, prefix completion via Tab, `/reset` and `/quit` slashes, and full PTY E2E coverage.

**Architecture:** The capstone is pure userland Ruby — it consumes the framework via `Cclikesh.run`. Three pure helper classes live in `examples/irb_shell/`: `IrbEvaluator` (delegates to `Binding#eval` against a persistent binding; `reset` swaps in a fresh binding so all locals/methods are dropped), `IrbCompleter` (prefix-match against `binding.local_variables` + `Object.constants` + `Kernel` methods — pragmatic completion that doesn't depend on `irb/completion` internals which churn across Ruby versions), `ByteCounter` (running byte total with K/M human format). The entry script `irb_shell.rb` wires them together using the spec §8.2 callback shape: `on_submit` opens a thinking live slot, evaluates the user's Ruby line, commits the live slot and prints the result on success or discards and prints the error on failure; `on_tab` calls completer; `info()` blocks render elapsed and tokens; `spinner_label` flips between `:auto` and `nil` keyed off `state[:phase]`; `/reset` clears evaluator+counter, `/quit` and `/q` exit.

**Note on `eval`:** This capstone is, by its nature, an interactive Ruby evaluator — running user-supplied Ruby is its purpose. The framework itself never evaluates user code; only the example impl does, and only against the user's own line input in their own process. We use `Binding#eval(line)` (the receiver-form method) which is the standard Ruby API for evaluating against a captured scope.

**Tech Stack:** Ruby 4.0.3, cclikesh framework (Plans 1-5), test-unit 3.6, PTY for E2E. No new gem dependencies.

**Position in roadmap:**
- Plans 1-5: framework feature-complete (foundation → dRuby split → display → runtime extensions → rendering)
- **Plan 6 (this): capstone — examples/irb_shell/ demonstrates end-to-end framework usage**

**Single-commit-per-task discipline:** Each task lands as ONE commit (test + impl). Conventional commit prefix in English.

---

### Task 1: `ByteCounter` — running byte counter with human format

**Files:**
- Create: `examples/irb_shell/byte_counter.rb`
- Test: `test/test_byte_counter.rb`

**Why:** Used by `info(:tokens)` block in irb_shell to display cumulative byte volume. Pure value object; no framework deps.

- [ ] **Step 1: Failing test in `test/test_byte_counter.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../examples/irb_shell/byte_counter"

class TestByteCounter < Test::Unit::TestCase
  def test_starts_at_zero
    counter = ByteCounter.new
    assert_equal 0, counter.bytes
  end

  def test_add_accumulates
    counter = ByteCounter.new
    counter.add(100)
    counter.add(50)
    assert_equal 150, counter.bytes
  end

  def test_reset_clears_total
    counter = ByteCounter.new
    counter.add(500)
    counter.reset
    assert_equal 0, counter.bytes
  end

  def test_human_under_1k_uses_b_suffix
    counter = ByteCounter.new
    counter.add(512)
    assert_equal "512b", counter.human
  end

  def test_human_kilobytes
    counter = ByteCounter.new
    counter.add(2048)
    assert_equal "2.0kb", counter.human
  end

  def test_human_megabytes
    counter = ByteCounter.new
    counter.add(2 * 1024 * 1024 + 100 * 1024)
    assert_equal "2.1mb", counter.human
  end
end
```

- [ ] **Step 2: Run — expect FAIL (file missing).**

```
bundle exec rake test TEST=test/test_byte_counter.rb
```

- [ ] **Step 3: Implement `examples/irb_shell/byte_counter.rb`**

```ruby
# frozen_string_literal: true

class ByteCounter
  attr_reader :bytes

  def initialize
    @bytes = 0
  end

  def add(n)
    @bytes += n
  end

  def reset
    @bytes = 0
  end

  def human
    if @bytes < 1024
      "#{@bytes}b"
    elsif @bytes < 1024 * 1024
      "#{(@bytes / 1024.0).round(1)}kb"
    else
      "#{(@bytes / (1024.0 * 1024.0)).round(1)}mb"
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS.**

Expected: 179 tests, 0 failures (173 + 6).

- [ ] **Step 5: Commit**

```bash
git add examples/irb_shell/byte_counter.rb test/test_byte_counter.rb
git commit -m "feat: add ByteCounter for irb capstone"
```

---

### Task 2: `IrbEvaluator` — Ruby evaluation with persistent binding

**Files:**
- Create: `examples/irb_shell/irb_evaluator.rb`
- Test: `test/test_irb_evaluator.rb`

**Why:** The evaluation engine. Variables defined in one submission must persist across submissions (`x = 1` then `x + 2` returns `3`). `reset` discards all locals.

- [ ] **Step 1: Failing test in `test/test_irb_evaluator.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../examples/irb_shell/irb_evaluator"

class TestIrbEvaluator < Test::Unit::TestCase
  def test_evaluates_simple_expression
    evaluator = IrbEvaluator.new
    assert_equal 3, evaluator.evaluate("1 + 2")
  end

  def test_persists_local_variables_across_calls
    evaluator = IrbEvaluator.new
    evaluator.evaluate("x = 10")
    assert_equal 30, evaluator.evaluate("x * 3")
  end

  def test_persists_method_definitions
    evaluator = IrbEvaluator.new
    evaluator.evaluate("def double(n); n * 2; end")
    assert_equal 8, evaluator.evaluate("double(4)")
  end

  def test_reset_clears_local_variables
    evaluator = IrbEvaluator.new
    evaluator.evaluate("x = 99")
    evaluator.reset
    assert_raise(NameError) { evaluator.evaluate("x") }
  end

  def test_binding_reader_exposes_current_binding
    evaluator = IrbEvaluator.new
    evaluator.evaluate("y = 7")
    assert_includes evaluator.binding.local_variables, :y
  end

  def test_evaluation_error_propagates
    evaluator = IrbEvaluator.new
    assert_raise(NameError) { evaluator.evaluate("undefined_var_xyz") }
  end

  def test_syntax_error_propagates_as_script_error
    evaluator = IrbEvaluator.new
    assert_raise(SyntaxError) { evaluator.evaluate("def broken(") }
  end
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `examples/irb_shell/irb_evaluator.rb`**

```ruby
# frozen_string_literal: true

class IrbEvaluator
  attr_reader :binding

  def initialize
    @binding = fresh_binding
  end

  def evaluate(line)
    @binding.eval(line)
  end

  def reset
    @binding = fresh_binding
  end

  private

  def fresh_binding
    Object.new.instance_eval { binding }
  end
end
```

(The `Binding#eval(line)` method is the standard Ruby API for executing user-supplied Ruby in a captured scope — exactly what an interactive shell needs. See "Note on `eval`" in the plan header for the security model.)

- [ ] **Step 4: Run — expect PASS.**

Expected: 186 tests, 0 failures (179 + 7).

- [ ] **Step 5: Commit**

```bash
git add examples/irb_shell/irb_evaluator.rb test/test_irb_evaluator.rb
git commit -m "feat: add IrbEvaluator with persistent binding"
```

---

### Task 3: `IrbCompleter` — prefix completion against binding + constants + Kernel

**Files:**
- Create: `examples/irb_shell/irb_completer.rb`
- Test: `test/test_irb_completer.rb`

**Why:** Powers `on_tab`. Pragmatic prefix-match over: local variables in the persistent binding, top-level `Object.constants`, Kernel instance methods. Avoids `irb/completion` whose API churns between Ruby versions, and uses no `eval` of user code (only the binding's metadata via `local_variables`).

- [ ] **Step 1: Failing test in `test/test_irb_completer.rb`**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../examples/irb_shell/irb_evaluator"
require_relative "../examples/irb_shell/irb_completer"

class TestIrbCompleter < Test::Unit::TestCase
  def test_completes_local_variable_in_binding
    evaluator = IrbEvaluator.new
    evaluator.evaluate("apple = 1")
    evaluator.evaluate("apricot = 2")
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("ap", 2)
    assert_includes candidates, "apple"
    assert_includes candidates, "apricot"
  end

  def test_completes_constant
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("Stri", 4)
    assert_includes candidates, "String"
  end

  def test_completes_kernel_method
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("put", 3)
    assert_includes candidates, "puts"
  end

  def test_returns_empty_when_no_word_at_pos
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    assert_empty completer.candidates("", 0)
    assert_empty completer.candidates("   ", 3)
  end

  def test_handles_pos_in_middle_of_buffer
    evaluator = IrbEvaluator.new
    evaluator.evaluate("foo = 1")
    completer = IrbCompleter.new(evaluator.binding)

    # buffer "fo bar", pos=2 — completing "fo"
    candidates = completer.candidates("fo bar", 2)
    assert_includes candidates, "foo"
  end

  def test_returns_unique_candidates
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("p", 1)
    assert_equal candidates.uniq, candidates
  end
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `examples/irb_shell/irb_completer.rb`**

```ruby
# frozen_string_literal: true

class IrbCompleter
  WORD_PATTERN = /[A-Za-z_][A-Za-z0-9_]*\z/.freeze

  def initialize(bind)
    @binding = bind
  end

  def candidates(buf, pos)
    prefix = buf[0...pos] || ""
    word = prefix[WORD_PATTERN]
    return [] if word.nil? || word.empty?

    pool = collect_pool
    pool.select { |c| c.start_with?(word) }.uniq
  end

  private

  def collect_pool
    locals = @binding.local_variables.map(&:to_s)
    constants = Object.constants.map(&:to_s)
    methods = Kernel.instance_methods.map(&:to_s) + Kernel.private_instance_methods.map(&:to_s)
    locals + constants + methods
  end
end
```

- [ ] **Step 4: Run — expect PASS.**

Expected: 192 tests, 0 failures (186 + 6).

- [ ] **Step 5: Commit**

```bash
git add examples/irb_shell/irb_completer.rb test/test_irb_completer.rb
git commit -m "feat: add IrbCompleter with binding-aware prefix completion"
```

---

### Task 4: `examples/irb_shell/irb_shell.rb` entry point

**Files:**
- Create: `examples/irb_shell/irb_shell.rb`
- Test: none (integration covered in Task 5 PTY E2E)

**Why:** The main script. Wires `Cclikesh.run` with all framework features end-to-end per spec §8.2: info segments (elapsed + tokens), spinner_label keyed off `state[:phase]`, on_submit (eval + live slot + error styling), on_tab (completer + dialog), `/reset / /quit / /q` slashes, format_duration helper.

- [ ] **Step 1: Implement `examples/irb_shell/irb_shell.rb`**

```ruby
# frozen_string_literal: true

require "cclikesh"
require_relative "irb_evaluator"
require_relative "irb_completer"
require_relative "byte_counter"

def format_duration(sec)
  m, s = sec.divmod(60)
  m.zero? ? "#{s.to_i}s" : "#{m.to_i}m #{s.to_i}s"
end

evaluator = IrbEvaluator.new
completer = IrbCompleter.new(evaluator.binding)
counter   = ByteCounter.new
start_at  = Time.now

Cclikesh.run do |shell|
  shell.on_submit do |line, ctx|
    ctx.display.append(line, prompt: "irb(main)> ")
    counter.add(line.bytesize)

    ctx.state[:phase] = :working
    slot = ctx.display.open_live(style: :thinking)
    slot.update("evaluating...")

    begin
      result = evaluator.evaluate(line)
      slot.commit
      ctx.display.append("=> #{result.inspect}", style: :result)
      counter.add(result.inspect.bytesize)
    rescue ScriptError, StandardError => e
      slot.discard
      ctx.display.append("#{e.class}: #{e.message}", style: :error)
      ctx.logger.error(e.full_message)
    ensure
      ctx.state[:phase] = :idle
    end
  end

  shell.on_tab do |buf, pos, ctx|
    candidates = completer.candidates(buf, pos)
    ctx.dialog.show(candidates.join("\n")) if candidates.size > 1
    candidates
  end

  shell.info(:elapsed, order: 10) { |_| format_duration(Time.now - start_at) }
  shell.info(:tokens,  order: 20) { |_| "↓ #{counter.human}" }

  shell.spinner_label do |ctx|
    ctx.state[:phase] == :working ? :auto : nil
  end

  shell.slash(:reset) do |_args, ctx|
    evaluator.reset
    counter.reset
    ctx.display.append("session reset", style: :result)
  end

  shell.slash(:quit) { |_args, ctx| ctx.quit }
  shell.slash(:q)    { |_args, ctx| ctx.quit }
end
```

- [ ] **Step 2: Smoke-launch the script briefly to verify no syntax errors at load time**

```bash
bundle exec ruby -Ilib -e 'load "examples/irb_shell/irb_shell.rb"' </dev/null 2>&1 | head -10
```

(Pipe `/dev/null` to stdin so the script's first `Reline.readline` returns `nil` and the shell exits cleanly. We just want to verify load works — don't care about the output as long as it doesn't error before reaching readline.)

If you see Ruby load errors (NameError, LoadError, SyntaxError), fix them. If the output looks like a normal cclikesh startup ending in EOF/exit, it's loading correctly.

- [ ] **Step 3: Run full test suite to confirm no regression**

```
bundle exec rake test
```

Expected: 192 tests, 0 failures (no new tests in this task — coverage in Task 5).

- [ ] **Step 4: Commit**

```bash
git add examples/irb_shell/irb_shell.rb
git commit -m "feat: add irb_shell.rb entry point integrating evaluator + completer + counter"
```

---

### Task 5: PTY E2E for irb_shell — types Ruby, asserts evaluated output

**Files:**
- Modify: `test/test_e2e_pty.rb`

**Why:** Capstone E2E. Spawns `irb_shell.rb` in a real PTY, types Ruby expressions, asserts the framework correctly produces evaluated output. Verifies the entire stack: dRuby + reline + tuple space + display + live slot + state + info bar + slash + binding persistence.

- [ ] **Step 1: Add E2E test methods to `test/test_e2e_pty.rb`**

```ruby
def test_irb_shell_evaluates_expressions_and_persists_bindings
  irb_shell = File.join(PROJECT_ROOT, "examples", "irb_shell", "irb_shell.rb")
  output = String.new
  pid = nil

  Timeout.timeout(30) do
    master, slave = PTY.open
    pid = spawn(
      "bundle", "exec", "ruby", "-Ilib", irb_shell,
      in: slave, out: slave, err: slave,
      chdir: PROJECT_ROOT
    )
    slave.close

    wait_for_prompt(master, output, 10)

    master.print "x = 41\r"
    sleep 0.3
    master.print "x + 1\r"
    sleep 0.3
    master.print "/q\r"

    drain_until_eof_or_timeout_for(master, output, 8, /=> 42/)
    Process.wait(pid)
    pid = nil
  end

  output.force_encoding("UTF-8") unless output.encoding == Encoding::UTF_8

  assert_match(/=> 41/, output, "first expression should yield => 41. Got:\n#{output.inspect}")
  assert_match(/=> 42/, output, "second expression should yield => 42 (persistent binding). Got:\n#{output.inspect}")
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

def test_irb_shell_reset_clears_bindings
  irb_shell = File.join(PROJECT_ROOT, "examples", "irb_shell", "irb_shell.rb")
  output = String.new
  pid = nil

  Timeout.timeout(30) do
    master, slave = PTY.open
    pid = spawn(
      "bundle", "exec", "ruby", "-Ilib", irb_shell,
      in: slave, out: slave, err: slave,
      chdir: PROJECT_ROOT
    )
    slave.close

    wait_for_prompt(master, output, 10)

    master.print "y = 100\r"
    sleep 0.3
    master.print "/reset\r"
    sleep 0.3
    master.print "y\r"
    sleep 0.3
    master.print "/q\r"

    drain_until_eof_or_timeout_for(master, output, 8, /NameError/)
    Process.wait(pid)
    pid = nil
  end

  output.force_encoding("UTF-8") unless output.encoding == Encoding::UTF_8

  assert_match(/=> 100/, output, "first assignment should yield => 100")
  assert_match(/session reset/, output, "/reset should print confirmation")
  assert_match(/NameError/, output, "after /reset, y should raise NameError")
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

- [ ] **Step 2: Run all tests**

```
bundle exec rake test
```

Expected: 194 tests, 0 failures (192 + 2).

If a test times out or output doesn't include the expected string:
- Increase `Timeout.timeout` first (PTY E2E can be slow on first run)
- Print `output.inspect` to see what actually came through
- Verify `examples/irb_shell/irb_shell.rb` runs manually with `bundle exec ruby -Ilib examples/irb_shell/irb_shell.rb`
- Check that `Reline.completer_word_break_characters = ""` (Plan 5 fix at commit `9c2c92c`) is being applied so completion routes correctly through dispatch_tab/on_submit

- [ ] **Step 3: Commit**

```bash
git add test/test_e2e_pty.rb
git commit -m "feat: add PTY E2E tests for irb_shell capstone"
```

---

## Self-Review Checklist (controller fills in before dispatch)

- **Spec coverage (§8):**
  - §8.1 directory structure `examples/irb_shell/{irb_shell.rb, irb_evaluator.rb, irb_completer.rb, byte_counter.rb}` (Tasks 1-4) ✅
  - §8.2 entry point: define_style ⚠️ deliberately omitted — irb_shell doesn't use a custom style; spec example showed it as API demonstration but per YAGNI we drop it
  - §8.2 on_submit with display.append + counter + state + live slot + result/error styling + logger.error (Task 4) ✅
  - §8.2 on_tab with completer + dialog.show (Task 4) ✅
  - §8.2 info(:elapsed) + info(:tokens) (Task 4) ✅
  - §8.2 spinner_label keyed off state[:phase] (Task 4) ✅
  - §8.2 slash(:reset) + slash(:quit) + slash(:q) (Task 4) ✅
  - §8.2 format_duration helper (Task 4) ✅
- **Placeholder scan:** All steps have concrete code or exact commands. ✅
- **Type consistency:**
  - `IrbEvaluator#binding`, `#evaluate(line)`, `#reset` — Tasks 2 → 3 → 4 use the same names ✅
  - `IrbCompleter.new(binding)` + `#candidates(buf, pos)` returns Array<String> — Task 3 → Task 4 use ✅
  - `ByteCounter#add(n)`, `#reset`, `#human`, `#bytes` — Tasks 1 → 4 use ✅
  - `format_duration(sec)` — Task 4 inline ✅
- **Single-commit-per-task:** All 5 tasks land as 1 commit each. ✅

---

## After Plan 6

The cclikesh framework is complete:
- 6 plans executed (foundation → dRuby split → display → runtime extensions → rendering → irb capstone)
- ~194 tests across all framework + capstone code
- Working `examples/echo_shell.rb` and `examples/irb_shell/irb_shell.rb` demonstrating the full DSL surface

The user's stated goal is met: **"Claude Code-style 3-region interactive CLI shell framework が完成、end2end で稼働して、ユーザーが活用できる"**.

Future enhancements (out of scope for current roadmap):
- Real overlay dialog rendering (vs. ASCII-box-in-history MVP)
- 60Hz spinner animation during live slot operation
- Idle phrase rotation on `idle_phrase_interval` timer
- `cclikesh/extras` layer (spinner presets, info segment helpers, built-in slash commands)
- More sophisticated completion using `irb/completion` API once it stabilizes across Ruby versions

These belong in a hypothetical Plan 7+ or `extras` layer, not the core framework.
