# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/event_thread"
require "cclikesh/tuple_space"

class TestEventThread < Test::Unit::TestCase
  def test_drains_state_change_and_calls_dispatch_state_change
    ts = Cclikesh::TupleSpace.new
    fake = []
    fake_registry = Object.new
    fake_registry.define_singleton_method(:dispatch_state_change) do |k, o, n, c|
      fake << [k, o, n, c]
    end

    thread = Cclikesh::EventThread.start(ts, registry: fake_registry, ctx: :ctx_sentinel)

    ts.write([:event, :state_change, :phase, nil, :working])

    deadline = Time.now + 1
    sleep 0.01 until !fake.empty? || Time.now > deadline

    ts.write([:cmd, :quit])
    assert_not_nil thread.join(2), "EventThread did not stop within 2s"

    assert_equal [[:phase, nil, :working, :ctx_sentinel]], fake
  end

  def test_drains_multiple_events_in_sequence
    ts = Cclikesh::TupleSpace.new
    fake = []
    fake_registry = Object.new
    fake_registry.define_singleton_method(:dispatch_state_change) do |k, o, n, _c|
      fake << [k, o, n]
    end

    thread = Cclikesh::EventThread.start(ts, registry: fake_registry, ctx: nil)

    [[:a, nil, 1], [:b, nil, 2], [:a, 1, 3]].each do |ev|
      ts.write([:event, :state_change, *ev])
      deadline = Time.now + 1
      prev = fake.size
      sleep 0.01 until fake.size > prev || Time.now > deadline
    end

    ts.write([:cmd, :quit])
    assert_not_nil thread.join(2), "EventThread did not stop within 2s"

    assert_equal [[:a, nil, 1], [:b, nil, 2], [:a, 1, 3]], fake
  end
end
