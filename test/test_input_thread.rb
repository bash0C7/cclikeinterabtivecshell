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
end
