# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/builder"
require "cclikesh/handler_registry"
require "cclikesh/context"
require "cclikesh/dispatcher"

class TestDispatcher < Test::Unit::TestCase
  def setup
    @ts = Cclikesh::TupleSpace.new
    @builder = Cclikesh::Builder.new
    @registry = Cclikesh::HandlerRegistry.new(@builder)
    @ctx = Cclikesh::Context.new(@ts)
    @dispatcher = Cclikesh::Dispatcher.new(@ts, @registry, @ctx)
  end

  def test_returns_quit_on_eof_key
    @ts.write([:key, nil])
    assert_equal :quit, @dispatcher.dispatch_one
  end

  def test_routes_plain_line_to_on_submit
    captured = []
    @builder.on_submit { |line, _ctx| captured << line }
    @ts.write([:key, "hello"])

    result = @dispatcher.dispatch_one

    assert_nil result
    assert_equal ["hello"], captured
  end

  def test_routes_slash_to_slash_handler
    captured = []
    @builder.slash(:greet) { |args, _ctx| captured << args }
    @ts.write([:key, "/greet alice bob"])

    @dispatcher.dispatch_one

    assert_equal [["alice", "bob"]], captured
  end

  def test_unknown_slash_appends_error_to_display
    @ts.write([:key, "/unknown"])

    @dispatcher.dispatch_one

    tuple = @ts.take([:render, :display_append, nil, nil], 1)
    assert_equal :display_append, tuple[1]
    assert_match(/\/unknown.*not registered/, tuple[2])
  end
end
