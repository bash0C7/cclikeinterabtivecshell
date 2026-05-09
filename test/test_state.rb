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

  def test_delete_removes_key_and_emits_state_change
    ts = Cclikesh::TupleSpace.new
    state = Cclikesh::State.new(ts)
    state[:phase] = :working
    drain_state_change_tuples(ts)

    state.delete(:phase)
    assert_nil state[:phase]
    _, _, key, old, new_v = ts.take([:event, :state_change, nil, nil, nil], 1)
    assert_equal :phase, key
    assert_equal :working, old
    assert_nil new_v
  end

  def test_delete_missing_key_is_noop
    ts = Cclikesh::TupleSpace.new
    state = Cclikesh::State.new(ts)
    state.delete(:never_set)
    assert_raise(Rinda::RequestExpiredError) do
      ts.take([:event, :state_change, nil, nil, nil], 0)
    end
  end

  def test_update_writes_each_changed_pair
    ts = Cclikesh::TupleSpace.new
    state = Cclikesh::State.new(ts)
    state.update(a: 1, b: 2)
    assert_equal 1, state[:a]
    assert_equal 2, state[:b]
  end

  def test_to_h_returns_snapshot
    ts = Cclikesh::TupleSpace.new
    state = Cclikesh::State.new(ts)
    state[:a] = 1
    state[:b] = "two"
    assert_equal({ a: 1, b: "two" }, state.to_h)
  end

  private

  def drain_state_change_tuples(ts)
    loop { ts.take([:event, :state_change, nil, nil, nil], 0) }
  rescue Rinda::RequestExpiredError
    # done
  end
end
