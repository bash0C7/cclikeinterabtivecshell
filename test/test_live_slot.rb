# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/live_slot"

class TestLiveSlot < Test::Unit::TestCase
  def setup
    @ts = Cclikesh::TupleSpace.new
    @slot = Cclikesh::LiveSlot.new(@ts, 1, style: :thinking)
  end

  def test_update_writes_live_update_tuple
    @slot.update("hi")
    tuple = @ts.take([:render, :live_update, 1, nil], 0)
    assert_equal [:render, :live_update, 1, "hi"], tuple
  end

  def test_commit_writes_live_commit_tuple_with_nil_final
    @slot.commit
    tuple = @ts.take([:render, :live_commit, 1, nil], 0)
    assert_equal [:render, :live_commit, 1, nil], tuple
  end

  def test_commit_as_writes_live_commit_tuple_with_final
    @slot.commit_as("done")
    tuple = @ts.take([:render, :live_commit, 1, nil], 0)
    assert_equal [:render, :live_commit, 1, "done"], tuple
  end

  def test_discard_writes_live_discard_tuple
    @slot.discard
    tuple = @ts.take([:render, :live_discard, 1], 0)
    assert_equal [:render, :live_discard, 1], tuple
  end

  def test_update_after_commit_is_noop
    @slot.commit
    @ts.take([:render, :live_commit, 1, nil], 0)
    @slot.update("ignored")
    assert_raise(Rinda::RequestExpiredError) do
      @ts.take([:render, :live_update, 1, nil], 0)
    end
  end

  def test_update_after_discard_is_noop
    @slot.discard
    @ts.take([:render, :live_discard, 1], 0)
    @slot.update("ignored")
    assert_raise(Rinda::RequestExpiredError) do
      @ts.take([:render, :live_update, 1, nil], 0)
    end
  end

  def test_double_commit_is_noop
    @slot.commit
    @ts.take([:render, :live_commit, 1, nil], 0)
    @slot.commit
    assert_raise(Rinda::RequestExpiredError) do
      @ts.take([:render, :live_commit, 1, nil], 0)
    end
  end

  def test_open_returns_true_committed_returns_false
    assert_equal true, @slot.open?
    @slot.commit
    assert_equal false, @slot.open?
  end

  def test_concurrent_updates_are_serialized
    threads = 10.times.map do |i|
      Thread.new { @slot.update("u#{i}") }
    end
    threads.each(&:join)

    collected = []
    loop { collected << @ts.take([:render, :live_update, 1, nil], 0) }
  rescue Rinda::RequestExpiredError
    assert_equal 10, collected.size
  end
end
