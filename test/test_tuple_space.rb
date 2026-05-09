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
