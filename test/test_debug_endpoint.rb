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
    sock = File.join(Dir.tmpdir, "test-debug-#{Process.pid}-#{rand(10000)}")
    ENV["CCLIKESH_DEBUG_SOCK"] = sock
    builder = Cclikesh::Builder.new
    Cclikesh::DebugEndpoint.start_if_enabled(builder)
    refute_nil Cclikesh::DebugEndpoint.adapter
  end

  def test_adapter_debug_snapshot_returns_hash_with_state
    require "tmpdir"
    require "logger"
    require "stringio"
    ENV["CCLIKESH_DEBUG_SOCK"] = File.join(Dir.tmpdir, "test-debug-snap-#{Process.pid}-#{rand(10000)}")
    Cclikesh::Context.reset!
    Cclikesh::Context.init(logger: Logger.new(StringIO.new))
    builder = Cclikesh::Builder.new
    builder.shortcuts_hint("? for help")
    Cclikesh::DebugEndpoint.start_if_enabled(builder)
    snap = Cclikesh::DebugEndpoint.adapter.debug_snapshot
    assert snap.key?(:framework_state)
    assert snap.key?(:ts_shell)
    assert_equal "? for help", snap[:framework_state][:shortcuts_hint]
  end

  def test_drain_events_returns_pushed_events
    require "tmpdir"
    require "logger"
    require "stringio"
    ENV["CCLIKESH_DEBUG_SOCK"] = File.join(Dir.tmpdir, "test-debug-events-#{Process.pid}-#{rand(10000)}")
    Cclikesh::Context.reset!
    Cclikesh::Context.init(logger: Logger.new(StringIO.new))
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
