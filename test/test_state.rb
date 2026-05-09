# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/state"

class TestState < Test::Unit::TestCase
  def test_set_and_get
    ts = Cclikesh::TupleSpace.new
    s = Cclikesh::State.new(ts)
    s[:phase] = :working
    assert_equal :working, s[:phase]
  end

  def test_get_unset_returns_nil
    ts = Cclikesh::TupleSpace.new
    s = Cclikesh::State.new(ts)
    assert_nil s[:nope]
  end

  def test_set_overwrites
    ts = Cclikesh::TupleSpace.new
    s = Cclikesh::State.new(ts)
    s[:phase] = :working
    s[:phase] = :idle
    assert_equal :idle, s[:phase]
  end
end
