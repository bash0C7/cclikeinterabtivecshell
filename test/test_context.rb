# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/context"

class TestContext < Test::Unit::TestCase
  def test_display_returns_a_display
    ts = Cclikesh::TupleSpace.new
    c = Cclikesh::Context.new(ts)
    assert_kind_of Cclikesh::Display, c.display
  end

  def test_state_returns_a_state
    ts = Cclikesh::TupleSpace.new
    c = Cclikesh::Context.new(ts)
    assert_kind_of Cclikesh::State, c.state
  end

  def test_quit_writes_cmd_quit_and_eof_key
    ts = Cclikesh::TupleSpace.new
    c = Cclikesh::Context.new(ts)
    c.quit
    assert_equal [:cmd, :quit], ts.take([:cmd, :quit])
    assert_equal [:key, nil], ts.take([:key, nil])
  end

  def test_display_and_state_are_memoized
    ts = Cclikesh::TupleSpace.new
    c = Cclikesh::Context.new(ts)
    assert_same c.display, c.display
    assert_same c.state, c.state
  end
end
