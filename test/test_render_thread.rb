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

  def test_render_thread_passes_registry_to_renderer
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    fake_reg = Object.new
    def fake_reg.style_definition(name); name == :ok ? { fg: :green } : nil; end

    th = Cclikesh::RenderThread.start(ts, out, tick_interval: 0.02, registry: fake_reg)
    ts.write([:render, :display_append, "yo", { style: :ok }])
    sleep 0.1
    ts.write([:cmd, :quit])
    th.join(2)

    assert_match(/\e\[32myo\e\[0m/, out.string)
  end

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
    assert_not_nil thread.join(2), "RenderThread did not stop within 2s"

    assert_match(/fast/, io.string)
    assert(elapsed < 1.5, "expected refresh to short-circuit 5s tick (got #{elapsed}s)")
  end
end
