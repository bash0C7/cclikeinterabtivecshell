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
