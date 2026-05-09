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
