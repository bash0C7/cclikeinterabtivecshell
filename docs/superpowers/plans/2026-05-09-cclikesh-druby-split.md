# cclikesh Plan 2 — dRuby split + reline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plan 1 の file-based I/O を捨てて、`fork` で impl process と F (framework) process に分離、UNIX socket dRuby で双方向通信、reline で real terminal 入力、stdout 出力で `examples/echo_shell.rb` が PTY 越しに動くまで持っていく。

**Architecture:**
- impl process (parent) が `Cclikesh.run do |shell| ... end` を起動 → Builder block で handler を登録 → `HandlerRegistry` を DRb-front 化 → `fork` → parent は `DRb.thread.join` で待機（remote call で handler が呼ばれる）。
- F process (child) は内部に `Rinda::TupleSpace` を持つ。`Context` / `Display` を DRb-front 化、impl 側へ proxy として渡す。F の dispatcher Thread は `ts.take([:key, ...])` で行を拾い、impl の `HandlerRegistry` を remote call。callback 内で impl が `ctx.display.append(...)` すると DRb 経由で F の TupleSpace に `[:render, :display_append, ...]` が書かれ、F の renderer Thread が drain して `$stdout` に書く。
- Plan 1 の Ractor 構成は Plan 2 では Thread + `Rinda::TupleSpace` に置換する（reline は terminal stdin を直接握るので Ractor 化は将来 Plan に回す）。`vendor/ts4r.rb` は撤去。

**Tech Stack:**
- Ruby 4.0.3
- `rinda/tuplespace` (Ruby stdlib に近い、gem 化されてる) — 双方向 dRuby 対応
- `drb` + `drb/unix` (stdlib)
- `reline` 0.5+ (gem)
- `pty` (stdlib) — E2E test 用
- test-unit 3.6

---

## File Structure

**新規:**
- `lib/cclikesh/endpoint.rb` — UNIX socket path generator (PID + tmpdir)
- `lib/cclikesh/handler_registry.rb` — impl 側で持つ DRb-front-able registry。`dispatch_submit(line, ctx)`, `dispatch_slash(name, args, ctx)`
- `lib/cclikesh/render_thread.rb` — Thread で render tuple を drain して IO に書く
- `lib/cclikesh/input_thread.rb` — Thread + Reline で行入力 → `[:key, line]` write
- `lib/cclikesh/forking.rb` — fork orchestration、parent/child branch、DRb 接続
- `test/test_endpoint.rb`
- `test/test_handler_registry.rb`
- `test/test_render_thread.rb`
- `test/test_e2e_pty.rb` — PTY 経由で echo_shell を起動して E2E
- `examples/echo_shell.rb` (overwrite — input/output_path 引数撤廃)

**修正:**
- `lib/cclikesh.rb` — `$LOAD_PATH.unshift` で vendor 削除、Cclikesh.run の signature 変更
- `lib/cclikesh/tuple_space.rb` — `Rinda::TupleSpace` 直に切替
- `lib/cclikesh/runner.rb` — fork orchestration 主導に書き換え
- `lib/cclikesh/dispatcher.rb` — handler 直 call → registry remote call
- `lib/cclikesh/context.rb` — `DRb::DRbUndumped` include
- `lib/cclikesh/display.rb` — `DRb::DRbUndumped` include
- `lib/cclikesh/state.rb` — `DRb::DRbUndumped` include（Plan 2 では使わんが API 互換維持）
- `lib/cclikesh/builder.rb` — `slash_handlers` を hash で expose（registry が読む）
- `lib/cclikesh/renderer.rb` — `try_take` 撤去、`Rinda::TupleSpace#take(pattern, 0)` + `RequestExpiredError` 補足
- `cclikesh.gemspec` — `add_dependency "rinda"`, `add_dependency "reline"` に変更（ts4r は無し）

**削除:**
- `lib/cclikesh/render_ractor.rb`
- `lib/cclikesh/input_ractor.rb`
- `lib/cclikesh/input_reader.rb`
- `vendor/ts4r.rb`
- `test/test_render_ractor.rb`
- `test/test_input_ractor.rb`
- `test/test_input_reader.rb`

---

## Tuple Schema (Plan 2 範囲)

| pattern | 書き手 | 読み手 |
|---|---|---|
| `[:key, line_or_nil]` | F input thread | F dispatcher thread |
| `[:render, :display_append, text, opts_hash]` | impl callback (DRb 経由) / dispatcher | F render thread |
| `[:cmd, :quit]` | impl (`ctx.quit` 経由) | F render/input/dispatcher |

Plan 1 の `[:event, :submit, line]` `[:event, :slash, ...]` は Plan 2 では一旦 emit 削除（observability 用途、Plan 4 で再導入する）。tests も合わせて削除。

---

### Task 1: vendor/ts4r 撤去 と Rinda::TupleSpace への切替

**Files:**
- Modify: `lib/cclikesh.rb`
- Modify: `lib/cclikesh/tuple_space.rb`
- Modify: `lib/cclikesh/renderer.rb`
- Modify: `cclikesh.gemspec`
- Delete: `vendor/ts4r.rb`
- Modify: `test/test_tuple_space.rb`
- Modify: `test/test_renderer.rb`

- [ ] **Step 1: gemspec を rinda + reline に**

`cclikesh.gemspec` の `add_dependency` を以下で置換:

```ruby
spec.add_dependency "rinda", "~> 0.2"
spec.add_dependency "reline", "~> 0.5"
```

- [ ] **Step 2: `lib/cclikesh.rb` から vendor 経路削除**

最終形:

```ruby
# frozen_string_literal: true

require_relative "cclikesh/version"
require_relative "cclikesh/runner"

module Cclikesh
  def self.run(&block)
    Runner.run(&block)
  end
end
```

- [ ] **Step 3: `lib/cclikesh/tuple_space.rb` を Rinda に**

```ruby
# frozen_string_literal: true

require "rinda/tuplespace"

module Cclikesh
  class TupleSpace
    def self.new
      Rinda::TupleSpace.new
    end
  end
end
```

- [ ] **Step 4: `lib/cclikesh/renderer.rb` を Rinda 直接呼び出しに**

`try_take` を `Rinda::TupleSpace#take(pattern, 0)` + `Rinda::RequestExpiredError` rescue に。LIFO 問題は Rinda::TupleSpace.bag は FIFO なので reverse 不要:

```ruby
# frozen_string_literal: true

require "rinda/tuplespace"

module Cclikesh
  class Renderer
    def initialize(tuple_space, output_io)
      @ts = tuple_space
      @out = output_io
    end

    def render_pending
      loop do
        tuple = @ts.take([:render, nil, nil, nil], 0)
        process(tuple)
      end
    rescue Rinda::RequestExpiredError
      # no more render tuples in this drain pass
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

- [ ] **Step 5: `vendor/ts4r.rb` 削除**

```bash
rm /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/vendor/ts4r.rb
rmdir /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/vendor 2>/dev/null || true
```

- [ ] **Step 6: `test/test_tuple_space.rb` を更新**

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"

class TestTupleSpace < Test::Unit::TestCase
  def test_returns_a_rinda_tuplespace
    ts = Cclikesh::TupleSpace.new
    assert_kind_of Rinda::TupleSpace, ts
  end

  def test_write_take_roundtrip
    ts = Cclikesh::TupleSpace.new
    ts.write([:hello, "world"])
    assert_equal [:hello, "world"], ts.take([:hello, nil])
  end
end
```

- [ ] **Step 7: `test/test_renderer.rb` を確認・更新**

既存の test 内容を確認して、`try_take` 想定なら `take(pattern, 0)` ベースに揃える。最低限以下のテストが pass する状態にする:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/tuple_space"
require "cclikesh/renderer"

class TestRenderer < Test::Unit::TestCase
  def test_render_pending_drains_display_append_tuples
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "first", {}])
    ts.write([:render, :display_append, "second", {}])

    r.render_pending

    assert_equal "first\nsecond\n", out.string
  end

  def test_render_pending_with_empty_queue_is_noop
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    r.render_pending

    assert_equal "", out.string
  end

  def test_render_pending_with_prompt_prefix
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "msg", { prompt: "> " }])

    r.render_pending

    assert_equal "> msg\n", out.string
  end
end
```

- [ ] **Step 8: テスト実行**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test 2>&1 | tail -20
```

Expected: TestTupleSpace と TestRenderer はパス。Plan 1 の `test_render_ractor.rb` `test_input_ractor.rb` `test_input_reader.rb` はまだ残ってるが Task 4 まで一旦そのまま、または skip。**実行時エラーで止まる場合は対象テストファイルを `git rm` する**：

```bash
git rm /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/test/test_render_ractor.rb \
       /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/test/test_input_ractor.rb \
       /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/test/test_input_reader.rb
```

その後再実行して全 green になること。

- [ ] **Step 9: Bundle install（rinda + reline 追加）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle install 2>&1 | tail -5
```

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: replace ts4r/Ractor with Rinda::TupleSpace"
```

---

### Task 2: Endpoint — DRb UNIX socket path generator

**Files:**
- Create: `lib/cclikesh/endpoint.rb`
- Create: `test/test_endpoint.rb`

- [ ] **Step 1: 失敗テストを書く**

`test/test_endpoint.rb`:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/endpoint"

class TestEndpoint < Test::Unit::TestCase
  def test_uri_is_drb_unix
    uri = Cclikesh::Endpoint.uri(:handlers)
    assert_match %r{\Adrbunix://}, uri
  end

  def test_uri_includes_role_name
    uri = Cclikesh::Endpoint.uri(:handlers)
    assert_match(/handlers/, uri)
  end

  def test_uri_is_unique_per_call_for_different_roles
    h = Cclikesh::Endpoint.uri(:handlers)
    c = Cclikesh::Endpoint.uri(:context)
    assert_not_equal h, c
  end

  def test_socket_path_in_tmpdir
    uri = Cclikesh::Endpoint.uri(:handlers)
    path = uri.sub(%r{\Adrbunix://}, "")
    assert_match(/\A#{Regexp.escape(Dir.tmpdir)}/, path)
  end
end
```

- [ ] **Step 2: テスト fail を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_endpoint.rb 2>&1 | tail -10
```

Expected: `cannot load such file -- cclikesh/endpoint`

- [ ] **Step 3: 実装**

`lib/cclikesh/endpoint.rb`:

```ruby
# frozen_string_literal: true

require "tmpdir"

module Cclikesh
  module Endpoint
    def self.uri(role)
      path = File.join(Dir.tmpdir, "cclikesh-#{Process.pid}-#{role}.sock")
      "drbunix://#{path}"
    end
  end
end
```

- [ ] **Step 4: テスト pass を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_endpoint.rb 2>&1 | tail -5
```

Expected: 4 tests, 4 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/endpoint.rb test/test_endpoint.rb
git commit -m "feat: add Endpoint DRb UNIX socket URI generator"
```

---

### Task 3: HandlerRegistry — impl 側 DRb-front-able registry

**Files:**
- Create: `lib/cclikesh/handler_registry.rb`
- Create: `test/test_handler_registry.rb`
- Modify: `lib/cclikesh/builder.rb`

- [ ] **Step 1: Builder を slash_handlers expose に修正**

`lib/cclikesh/builder.rb`:

```ruby
# frozen_string_literal: true

module Cclikesh
  class Builder
    attr_reader :on_submit_handler, :slash_handlers

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

- [ ] **Step 2: 失敗テストを書く**

`test/test_handler_registry.rb`:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/builder"
require "cclikesh/handler_registry"

class TestHandlerRegistry < Test::Unit::TestCase
  def test_dispatch_submit_calls_on_submit_handler_with_line_and_ctx
    builder = Cclikesh::Builder.new
    captured = []
    builder.on_submit { |line, ctx| captured << [line, ctx] }

    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_submit("hello", :stub_ctx)

    assert_equal [["hello", :stub_ctx]], captured
  end

  def test_dispatch_submit_with_no_handler_is_noop
    builder = Cclikesh::Builder.new
    registry = Cclikesh::HandlerRegistry.new(builder)

    assert_nothing_raised do
      registry.dispatch_submit("hi", :stub_ctx)
    end
  end

  def test_dispatch_slash_calls_registered_handler_with_args_and_ctx
    builder = Cclikesh::Builder.new
    captured = []
    builder.slash(:greet) { |args, ctx| captured << [args, ctx] }

    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_slash(:greet, ["alice"], :stub_ctx)

    assert_equal [[["alice"], :stub_ctx]], captured
  end

  def test_dispatch_slash_returns_not_registered_for_unknown
    builder = Cclikesh::Builder.new
    registry = Cclikesh::HandlerRegistry.new(builder)

    assert_equal :not_registered, registry.dispatch_slash(:unknown, [], :stub_ctx)
  end
end
```

- [ ] **Step 3: テスト fail を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_handler_registry.rb 2>&1 | tail -10
```

Expected: load error.

- [ ] **Step 4: 実装**

`lib/cclikesh/handler_registry.rb`:

```ruby
# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class HandlerRegistry
    include DRb::DRbUndumped

    def initialize(builder)
      @builder = builder
    end

    def dispatch_submit(line, ctx)
      handler = @builder.on_submit_handler
      handler.call(line, ctx) if handler
      nil
    end

    def dispatch_slash(name, args, ctx)
      handler = @builder.slash_handler(name)
      return :not_registered unless handler
      handler.call(args, ctx)
      nil
    end
  end
end
```

- [ ] **Step 5: テスト pass を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_handler_registry.rb 2>&1 | tail -5
```

Expected: 4 tests, 5 assertions, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/cclikesh/builder.rb lib/cclikesh/handler_registry.rb test/test_handler_registry.rb
git commit -m "feat: add HandlerRegistry as DRb-front for impl callbacks"
```

---

### Task 4: Context / Display / State を DRb-front-able に

**Files:**
- Modify: `lib/cclikesh/context.rb`
- Modify: `lib/cclikesh/display.rb`
- Modify: `lib/cclikesh/state.rb`
- Modify: `test/test_context.rb`

- [ ] **Step 1: Display に DRbUndumped**

`lib/cclikesh/display.rb`:

```ruby
# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class Display
    include DRb::DRbUndumped

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

- [ ] **Step 2: State に DRbUndumped**

`lib/cclikesh/state.rb`:

```ruby
# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class State
    include DRb::DRbUndumped

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

- [ ] **Step 3: Context に DRbUndumped**

`lib/cclikesh/context.rb`:

```ruby
# frozen_string_literal: true

require "drb/drb"
require_relative "display"
require_relative "state"

module Cclikesh
  class Context
    include DRb::DRbUndumped

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
      @ts.write([:key, nil])
    end
  end
end
```

- [ ] **Step 4: 既存テストが pass することを確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_context.rb 2>&1 | tail -5
```

Expected: 4 tests, 6 assertions, 0 failures（DRbUndumped は単に marker mixin、既存挙動は変わらん）。

- [ ] **Step 5: 全 test 実行で regression 無しを確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test 2>&1 | tail -10
```

Expected: 全 green。

- [ ] **Step 6: Commit**

```bash
git add lib/cclikesh/context.rb lib/cclikesh/display.rb lib/cclikesh/state.rb
git commit -m "feat: mark Context/Display/State as DRbUndumped for proxy semantics"
```

---

### Task 5: RenderThread — Thread 版 renderer

**Files:**
- Create: `lib/cclikesh/render_thread.rb`
- Create: `test/test_render_thread.rb`

- [ ] **Step 1: 失敗テストを書く**

`test/test_render_thread.rb`:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/tuple_space"
require "cclikesh/render_thread"

class TestRenderThread < Test::Unit::TestCase
  def test_drains_display_append_tuples_and_stops_on_quit
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new

    thread = Cclikesh::RenderThread.start(ts, out, tick_interval: 0.02)

    ts.write([:render, :display_append, "alpha", {}])
    ts.write([:render, :display_append, "beta", {}])

    sleep 0.1
    ts.write([:cmd, :quit])
    thread.join(1)

    assert_false thread.alive?, "render thread should have exited after [:cmd, :quit]"
    assert_match(/alpha/, out.string)
    assert_match(/beta/, out.string)
  end

  def test_quit_with_no_pending_tuples_still_exits
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    thread = Cclikesh::RenderThread.start(ts, out, tick_interval: 0.02)

    ts.write([:cmd, :quit])
    thread.join(1)

    assert_false thread.alive?
  end
end
```

- [ ] **Step 2: テスト fail を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_render_thread.rb 2>&1 | tail -10
```

Expected: load error.

- [ ] **Step 3: 実装**

`lib/cclikesh/render_thread.rb`:

```ruby
# frozen_string_literal: true

require_relative "renderer"

module Cclikesh
  class RenderThread
    def self.start(ts, output_io, tick_interval: 0.06)
      Thread.new do
        renderer = Renderer.new(ts, output_io)
        stopping = false
        watcher = Thread.new do
          ts.read([:cmd, :quit])
          stopping = true
        end
        until stopping
          sleep tick_interval
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

- [ ] **Step 4: テスト pass を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_render_thread.rb 2>&1 | tail -5
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/render_thread.rb test/test_render_thread.rb
git commit -m "feat: add RenderThread that drains render tuples to IO"
```

---

### Task 6: InputThread — reline で行入力 → tuple

**Files:**
- Create: `lib/cclikesh/input_thread.rb`
- Create: `test/test_input_thread.rb`

- [ ] **Step 1: 失敗テストを書く**

reline の terminal 依存性を回避するため、InputThread には `reader_proc` を渡せる設計にする（real run では `Reline.method(:readline)` を渡し、test では IO.gets ベースの lambda を渡す）。

`test/test_input_thread.rb`:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/input_thread"

class TestInputThread < Test::Unit::TestCase
  def test_emits_key_tuples_per_line_and_eof
    ts = Cclikesh::TupleSpace.new
    lines = ["first", "second", nil] # nil signals EOF
    idx = 0
    reader = lambda do |_prompt|
      v = lines[idx]
      idx += 1
      raise "reader called too many times" if idx > lines.size
      v
    end

    thread = Cclikesh::InputThread.start(ts, reader: reader, prompt: "> ")
    thread.join(1)

    assert_equal [:key, "first"],  ts.take([:key, "first"])
    assert_equal [:key, "second"], ts.take([:key, "second"])
    assert_equal [:key, nil],      ts.take([:key, nil])
    assert_false thread.alive?
  end

  def test_stops_on_cmd_quit_before_next_read
    ts = Cclikesh::TupleSpace.new
    reader_calls = 0
    reader = lambda do |_prompt|
      reader_calls += 1
      sleep 0.05
      "x"
    end

    thread = Cclikesh::InputThread.start(ts, reader: reader, prompt: "> ")
    ts.write([:cmd, :quit])
    thread.join(1)

    assert_false thread.alive?
  end
end
```

- [ ] **Step 2: テスト fail を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_input_thread.rb 2>&1 | tail -10
```

Expected: load error.

- [ ] **Step 3: 実装**

`lib/cclikesh/input_thread.rb`:

```ruby
# frozen_string_literal: true

module Cclikesh
  class InputThread
    def self.start(ts, reader:, prompt: "> ")
      Thread.new do
        loop do
          # Check for quit signal before blocking on read.
          quit_tuple = ts.read([:cmd, :quit], 0) rescue nil
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

- [ ] **Step 4: テスト pass を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_input_thread.rb 2>&1 | tail -5
```

Expected: 2 tests, 0 failures.

注: 2 番目のテスト `test_stops_on_cmd_quit_before_next_read` は reader が走った後に quit が書かれる race があり得る。失敗するなら reader を `sleep 0.2` に伸ばし、test 内 sleep を増やす。それでも flaky なら、test を「`[:cmd, :quit]` 書いた後 thread が短時間で死ぬこと」だけにして、reader_calls の値は assert しない。

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/input_thread.rb test/test_input_thread.rb
git commit -m "feat: add InputThread with injectable reader for reline integration"
```

---

### Task 7: Dispatcher を HandlerRegistry remote call に切替

**Files:**
- Modify: `lib/cclikesh/dispatcher.rb`
- Modify: `test/test_dispatcher.rb`

- [ ] **Step 1: 既存 test を確認**

```bash
cat /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/test/test_dispatcher.rb
```

現状は `Dispatcher.new(ts, builder, ctx)` 想定の test。これを `Dispatcher.new(ts, registry, ctx)` 想定に書き換える。

- [ ] **Step 2: test を書き換える**

`test/test_dispatcher.rb` の全置換:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/builder"
require "cclikesh/handler_registry"
require "cclikesh/context"
require "cclikesh/dispatcher"

class TestDispatcher < Test::Unit::TestCase
  def setup
    @ts = Cclikesh::TupleSpace.new
    @builder = Cclikesh::Builder.new
    @registry = Cclikesh::HandlerRegistry.new(@builder)
    @ctx = Cclikesh::Context.new(@ts)
    @dispatcher = Cclikesh::Dispatcher.new(@ts, @registry, @ctx)
  end

  def test_returns_quit_on_eof_key
    @ts.write([:key, nil])
    assert_equal :quit, @dispatcher.dispatch_one
  end

  def test_routes_plain_line_to_on_submit
    captured = []
    @builder.on_submit { |line, _ctx| captured << line }
    @ts.write([:key, "hello"])

    result = @dispatcher.dispatch_one

    assert_nil result
    assert_equal ["hello"], captured
  end

  def test_routes_slash_to_slash_handler
    captured = []
    @builder.slash(:greet) { |args, _ctx| captured << args }
    @ts.write([:key, "/greet alice bob"])

    @dispatcher.dispatch_one

    assert_equal [["alice", "bob"]], captured
  end

  def test_unknown_slash_appends_error_to_display
    @ts.write([:key, "/unknown"])

    @dispatcher.dispatch_one

    tuple = @ts.take([:render, :display_append, nil, nil], 1)
    assert_equal :display_append, tuple[1]
    assert_match(/\/unknown.*not registered/, tuple[2])
  end
end
```

- [ ] **Step 3: テスト fail を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_dispatcher.rb 2>&1 | tail -15
```

Expected: 既存 dispatcher が builder 直アクセスなので tests pass する可能性もあるが、API シグネチャ変更（builder → registry）で fail。

- [ ] **Step 4: 実装書き換え**

`lib/cclikesh/dispatcher.rb`:

```ruby
# frozen_string_literal: true

module Cclikesh
  class Dispatcher
    def initialize(tuple_space, registry, context)
      @ts = tuple_space
      @registry = registry
      @ctx = context
    end

    def dispatch_one
      _, payload = @ts.take([:key, nil])
      return :quit if payload.nil?

      if payload.start_with?("/")
        dispatch_slash(payload)
      else
        @registry.dispatch_submit(payload, @ctx)
      end
      nil
    end

    private

    def dispatch_slash(payload)
      name_part, *args = payload[1..].split(/\s+/)
      name = name_part.to_sym
      result = @registry.dispatch_slash(name, args, @ctx)
      if result == :not_registered
        @ctx.display.append("/#{name}: not registered", style: :error)
      end
    end
  end
end
```

- [ ] **Step 5: テスト pass を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_dispatcher.rb 2>&1 | tail -5
```

Expected: 4 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/cclikesh/dispatcher.rb test/test_dispatcher.rb
git commit -m "refactor: route Dispatcher through HandlerRegistry"
```

---

### Task 8: Forking — fork + DRb wiring

**Files:**
- Create: `lib/cclikesh/forking.rb`
- Create: `test/test_forking.rb`

設計:
- `Forking.run(builder, &child_block)` を提供
  - parent (impl) 側: `DRb.start_service(handlers_uri, registry)` → `fork` → child branch では何もせず即 `child_block` を呼ぶ前に `DRb.thread.join`
  - child (F) 側: child_block.call(handlers_uri) を呼ぶ。child_block 中で F 起動シーケンスを走らせる
  - child 終了で parent に SIGCHLD → parent `Process.wait(child_pid)` → DRb stop → return

- [ ] **Step 1: 失敗テストを書く**

`test/test_forking.rb`:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/builder"
require "cclikesh/handler_registry"
require "cclikesh/forking"

class TestForking < Test::Unit::TestCase
  def test_child_can_call_registry_via_drb_and_handler_runs_in_parent
    builder = Cclikesh::Builder.new
    received = nil
    builder.on_submit do |line, _ctx|
      File.write("/tmp/cclikesh-fork-test-#{Process.pid}.txt", "got:#{line}")
      received = line
    end
    registry = Cclikesh::HandlerRegistry.new(builder)
    parent_pid = Process.pid

    Cclikesh::Forking.run(registry) do |handlers_uri|
      # child side: connect, dispatch, exit
      require "drb/drb"
      require "drb/unix"
      DRb.start_service
      remote = DRbObject.new_with_uri(handlers_uri)
      remote.dispatch_submit("hello-from-child", nil)
      exit 0
    end

    path = "/tmp/cclikesh-fork-test-#{parent_pid}.txt"
    assert_path_exist path
    assert_equal "got:hello-from-child", File.read(path)
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
```

- [ ] **Step 2: テスト fail を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_forking.rb 2>&1 | tail -10
```

Expected: load error.

- [ ] **Step 3: 実装**

`lib/cclikesh/forking.rb`:

```ruby
# frozen_string_literal: true

require "drb/drb"
require "drb/unix"
require_relative "endpoint"

module Cclikesh
  module Forking
    # Spawn an F process via fork. The parent serves `registry` over a
    # UNIX-socket DRb endpoint; the child receives that URI and runs `child_block`.
    # Returns when the child exits.
    def self.run(registry)
      handlers_uri = Endpoint.uri(:handlers)
      DRb.start_service(handlers_uri, registry)

      child_pid = fork do
        DRb.stop_service # detach from inherited service
        yield handlers_uri
      end

      Process.wait(child_pid)
      DRb.stop_service
      $?
    end
  end
end
```

- [ ] **Step 4: テスト pass を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_forking.rb 2>&1 | tail -10
```

Expected: 1 test, 2 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh/forking.rb test/test_forking.rb
git commit -m "feat: add Forking with parent DRb service and child branch"
```

---

### Task 9: Runner を fork orchestration に書き換え

**Files:**
- Modify: `lib/cclikesh/runner.rb`
- Modify: `lib/cclikesh.rb`
- Create: `test/test_runner_smoke.rb`（既存 smoke test を更新する形）

設計:

```
Cclikesh.run do |shell|
  shell.on_submit { |line, ctx| ctx.display.append("you said: #{line}") }
  shell.slash(:quit) { |_args, ctx| ctx.quit }
end
```

の中で:
1. Builder 実行 → handler 登録
2. HandlerRegistry を作る
3. Forking.run(registry) ブロック内 (child = F):
   a. TupleSpace.new
   b. Context.new(ts)
   c. Dispatcher.new(ts, registry_proxy, ctx)
   d. RenderThread.start(ts, $stdout)
   e. InputThread.start(ts, reader: Reline.method(:readline))
   f. dispatcher.dispatch_one ループ → :quit で break
   g. ts.write([:cmd, :quit])
   h. render thread / input thread join
4. parent は Forking.run の中で Process.wait

- [ ] **Step 1: lib/cclikesh.rb を最終形に**

```ruby
# frozen_string_literal: true

require_relative "cclikesh/version"
require_relative "cclikesh/runner"

module Cclikesh
  def self.run(&block)
    Runner.run(&block)
  end
end
```

- [ ] **Step 2: lib/cclikesh/runner.rb を書き換え**

```ruby
# frozen_string_literal: true

require "drb/drb"
require "drb/unix"
require "reline"
require_relative "tuple_space"
require_relative "builder"
require_relative "context"
require_relative "dispatcher"
require_relative "handler_registry"
require_relative "forking"
require_relative "render_thread"
require_relative "input_thread"

module Cclikesh
  class Runner
    def self.run(tick_interval: 0.06, &block)
      builder = Builder.new
      block.call(builder)
      registry = HandlerRegistry.new(builder)

      Forking.run(registry) do |handlers_uri|
        run_child(handlers_uri, tick_interval: tick_interval)
      end
    end

    def self.run_child(handlers_uri, tick_interval:)
      DRb.start_service
      registry_remote = DRbObject.new_with_uri(handlers_uri)

      ts = TupleSpace.new
      ctx = Context.new(ts)
      dispatcher = Dispatcher.new(ts, registry_remote, ctx)

      render_thread = RenderThread.start(ts, $stdout, tick_interval: tick_interval)
      input_thread  = InputThread.start(ts, reader: Reline.method(:readline), prompt: "> ")

      loop do
        break if dispatcher.dispatch_one == :quit
      end

      ts.write([:cmd, :quit])
      render_thread.join(2)
      input_thread.join(2)
      DRb.stop_service
    end
  end
end
```

- [ ] **Step 3: 旧 smoke test 撤去または更新**

既存の smoke test `test/test_smoke.rb` を確認:

```bash
ls /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/test/test_smoke.rb 2>/dev/null && cat /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/test/test_smoke.rb || echo "no smoke test"
```

旧 smoke test が input_path/output_path 想定なら削除:

```bash
git rm /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell/test/test_smoke.rb 2>/dev/null || true
```

E2E は Task 11 で PTY ベースで書き直す。

- [ ] **Step 4: 全 test を実行（runner は test 対象外）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test 2>&1 | tail -10
```

Expected: 全 green。Runner 自体は PTY E2E でカバーする。

- [ ] **Step 5: Commit**

```bash
git add lib/cclikesh.rb lib/cclikesh/runner.rb
git rm -f test/test_smoke.rb 2>/dev/null || true
git commit -m "refactor: rewrite Runner to fork impl/F and run reline + render threads"
```

---

### Task 10: examples/echo_shell.rb を新 API に

**Files:**
- Modify: `examples/echo_shell.rb`

- [ ] **Step 1: 書き換え**

`examples/echo_shell.rb`:

```ruby
# frozen_string_literal: true

require "cclikesh"

Cclikesh.run do |shell|
  shell.on_submit do |line, ctx|
    ctx.display.append("you said: #{line}")
  end

  shell.slash(:quit) do |_args, ctx|
    ctx.quit
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add examples/echo_shell.rb
git commit -m "refactor: simplify echo_shell example to new fork+reline API"
```

---

### Task 11: PTY E2E test

**Files:**
- Create: `test/test_e2e_pty.rb`

PTY (`require "pty"`) で `bundle exec ruby examples/echo_shell.rb` を起動、行を流して output を assert。

- [ ] **Step 1: テストを書く**

`test/test_e2e_pty.rb`:

```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "pty"
require "timeout"

class TestE2EPTY < Test::Unit::TestCase
  ECHO_SHELL = File.expand_path("../examples/echo_shell.rb", __dir__)

  def test_echo_then_quit_produces_expected_output
    output = ""
    Timeout.timeout(15) do
      PTY.spawn(RbConfig.ruby, "-Ilib", ECHO_SHELL) do |r, w, _pid|
        # Wait for first prompt to appear
        wait_for(r, /> /, timeout: 5)
        w.puts "hello"
        sleep 0.3
        w.puts "/quit"

        loop do
          chunk = r.read_nonblock(4096) rescue nil
          break if chunk.nil?
          output << chunk
          break if output.include?("you said: hello")
        end

        # Drain remaining output until EOF
        loop do
          chunk = r.readpartial(4096) rescue break
          output << chunk
        end
      end
    end

    assert_match(/you said: hello/, output, "expected echoed line in PTY output. Got:\n#{output.inspect}")
  end

  private

  def wait_for(io, regex, timeout: 3)
    buf = ""
    deadline = Time.now + timeout
    until buf =~ regex
      raise "timeout waiting for #{regex.inspect} (got #{buf.inspect})" if Time.now > deadline
      ready = IO.select([io], nil, nil, 0.1)
      next unless ready
      chunk = io.read_nonblock(4096) rescue nil
      buf << chunk if chunk
    end
    buf
  end
end
```

- [ ] **Step 2: 実行**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test TEST=test/test_e2e_pty.rb 2>&1 | tail -30
```

Expected: 1 test, 1 assertion, 0 failures。

失敗時のデバッグ:
- output に prompt `> ` が出てるか
- `you said: hello` まで届いてるか
- timeout なら reline がブロックしてる可能性 → echo_shell の `puts "ready"` を追加して prompt 検出を切り替える
- reline が PTY 環境で適切に動かない場合、fallback として `STDIN.tty?` チェックして `STDIN.gets` に切り替える runner option を入れる

- [ ] **Step 3: 全 test 実行（regression check）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cclikeinterabtivecshell && bundle exec rake test 2>&1 | tail -10
```

Expected: 全 green。

- [ ] **Step 4: Commit**

```bash
git add test/test_e2e_pty.rb
git commit -m "test: add PTY-driven E2E for echo_shell"
```

---

### Task 12: README 更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README を Plan 2 状態に更新**

Plan 2 完了後の状態を反映する: file-based I/O 廃止、real terminal で動く、PTY E2E あり。

`README.md` の "Status" / "Try the example" / "Roadmap" 部分を更新:

- Status: "Plan 2 (dRuby split + reline) complete. F process forks from impl, reline drives stdin, stdout receives rendered output, PTY E2E green."
- Try the example: `ruby -Ilib examples/echo_shell.rb` を直接 terminal で叩けば動く（input/output_path 引数不要）
- Roadmap: Plan 3 (3-region rendering with Display engine) を次に位置付け

具体的な diff は既存 README を読んでから対応する箇所だけ書き換える。

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for Plan 2 fork+reline architecture"
```

---

## Self-Review Notes

**Spec coverage (section 4.6):**
- ✅ fork で impl/F 分離 → Task 8, 9
- ✅ UNIX socket dRuby → Task 8, 9
- ✅ HandlerRegistry → Task 3
- ✅ Context DRb-front → Task 4
- ✅ reline 統合 → Task 6, 9
- ⏭ Ractor (Input/Render/Logger/Main) → Plan 2 では Thread 化、後の Plan で再導入の余地
- ⏭ tcsetpgrp による terminal 制御譲渡 → Plan 2 では PTY 内で十分。明示制御は Plan 3 以降
- ⏭ Logger Ractor / log tuple → Plan 5 (Logger+Box)

**スコープ check:**
- 4.6 の中でも Ractor 並列化は Plan 2 範囲外と明確に分離（Thread で代替）。これにより Plan 2 が完結する。

**型/シグネチャ整合性:**
- `HandlerRegistry#dispatch_submit(line, ctx)` Task 3, 7, 8 で一致
- `HandlerRegistry#dispatch_slash(name, args, ctx)` 同上
- `Forking.run(registry) { |uri| ... }` Task 8, 9 で一致
- `Cclikesh.run(tick_interval: 0.06, &block)` Task 9 でのみ定義（input/output_path 撤廃）
- `RenderThread.start(ts, io, tick_interval:)` Task 5, 9 一致
- `InputThread.start(ts, reader:, prompt:)` Task 6, 9 一致

**プレースホルダー scan:** なし。
