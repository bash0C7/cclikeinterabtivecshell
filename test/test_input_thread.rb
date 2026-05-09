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

  def test_stops_when_quit_tuple_present_before_next_read
    ts = Cclikesh::TupleSpace.new
    ts.write([:cmd, :quit]) # quit already pending before thread starts

    reader_calls = 0
    reader = lambda do |_prompt|
      reader_calls += 1
      "should-not-happen"
    end

    thread = Cclikesh::InputThread.start(ts, reader: reader, prompt: "> ")
    thread.join(1)

    assert_false thread.alive?
    assert_equal 0, reader_calls, "reader should not be invoked when quit is already pending"
  end

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
end
