# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/builder"
require "cclikesh/context"
require "cclikesh/dispatcher"

class TestDispatcher < Test::Unit::TestCase
  def test_dispatch_one_calls_on_submit_handler
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    received = []
    builder.on_submit { |line, ctx| received << line }
    ts.write([:key, "hello"])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    d.dispatch_one
    assert_equal ["hello"], received
  end

  def test_dispatch_one_calls_slash_handler_for_known_command
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    quit_called = false
    builder.slash(:quit) { |args, ctx| quit_called = true; ctx.quit }
    ts.write([:key, "/quit"])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    d.dispatch_one
    assert quit_called, "slash handler must be called"
  end

  def test_dispatch_one_writes_error_for_unknown_slash
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    ts.write([:key, "/unknown"])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    d.dispatch_one
    tuple = ts.take([:render, :display_append, nil, nil])
    assert_equal :display_append, tuple[1]
    assert_match(/unknown/, tuple[2])
  end

  def test_dispatch_one_returns_quit_when_eof_key_seen
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    ts.write([:key, nil])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    result = d.dispatch_one
    assert_equal :quit, result
  end

  def test_dispatch_one_with_no_on_submit_does_not_raise
    ts = Cclikesh::TupleSpace.new
    builder = Cclikesh::Builder.new
    ts.write([:key, "hello"])
    ctx = Cclikesh::Context.new(ts)
    d = Cclikesh::Dispatcher.new(ts, builder, ctx)
    assert_nothing_raised { d.dispatch_one }
  end
end
