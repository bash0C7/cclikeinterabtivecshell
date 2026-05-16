# frozen_string_literal: true

require_relative "test_helper"
require "baslash/builder"
require "baslash/context"
require "baslash/main_ctx"
require "baslash/transcript"
require "baslash/debug_endpoint"

class TestDebugEndpointBaslash < Test::Unit::TestCase
  def teardown
    Baslash::DebugEndpoint.stop_for_test
    ENV.delete("BASLASH_DEBUG_SOCK")
  end

  def test_start_does_nothing_without_env
    builder = Baslash::Builder.new
    Baslash::DebugEndpoint.start_if_enabled(builder)
    assert_nil Baslash::DebugEndpoint.adapter
  end

  def test_start_creates_adapter_when_env_set
    require "tmpdir"
    sock = File.join(Dir.tmpdir, "test-debug-#{Process.pid}-#{rand(10000)}")
    ENV["BASLASH_DEBUG_SOCK"] = sock
    builder = Baslash::Builder.new
    Baslash::DebugEndpoint.start_if_enabled(builder)
    refute_nil Baslash::DebugEndpoint.adapter
  end

  def test_adapter_debug_snapshot_returns_hash_with_state
    require "tmpdir"
    require "logger"
    require "stringio"
    ENV["BASLASH_DEBUG_SOCK"] = File.join(Dir.tmpdir, "test-debug-snap-#{Process.pid}-#{rand(10000)}")
    Baslash::Context.reset!
    Baslash::Context.init(logger: Logger.new(StringIO.new))
    builder = Baslash::Builder.new
    builder.shortcuts_hint("? for help")
    Baslash::DebugEndpoint.start_if_enabled(builder)
    snap = Baslash::DebugEndpoint.adapter.debug_snapshot
    assert snap.key?(:framework_state)
    assert snap.key?(:cursor)
    assert snap.key?(:ts_shell)
    assert_equal "? for help", snap[:framework_state][:shortcuts_hint]
  end

  def test_drain_events_returns_pushed_events
    require "tmpdir"
    require "logger"
    require "stringio"
    ENV["BASLASH_DEBUG_SOCK"] = File.join(Dir.tmpdir, "test-debug-events-#{Process.pid}-#{rand(10000)}")
    Baslash::Context.reset!
    Baslash::Context.init(logger: Logger.new(StringIO.new))
    Baslash::DebugEndpoint.start_if_enabled(Baslash::Builder.new)
    Baslash::DebugEndpoint.adapter.push_event(:input_received, line: "hello")
    Baslash::DebugEndpoint.adapter.push_event(:render_commit)
    events = Baslash::DebugEndpoint.adapter.debug_drain_events
    assert_equal 2, events.size
    assert_equal :input_received, events[0][:kind]
    assert_equal "hello", events[0][:payload][:line]
    assert_equal :render_commit, events[1][:kind]
    assert_empty Baslash::DebugEndpoint.adapter.debug_drain_events
  end
end
