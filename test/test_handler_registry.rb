# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/builder"
require "cclikesh/handler_registry"

class TestHandlerRegistry < Test::Unit::TestCase
  def test_dispatch_submit_calls_on_submit_handler_with_line_and_ctx
    builder = Cclikesh::Builder.new
    captured = []
    builder.on_submit { |line, ctx| captured << [line, ctx] }

    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_submit("hello", :stub_ctx)

    assert_equal [["hello", :stub_ctx]], captured
  end

  def test_dispatch_submit_with_no_handler_is_noop
    builder = Cclikesh::Builder.new
    registry = Cclikesh::HandlerRegistry.new(builder)

    assert_nothing_raised do
      registry.dispatch_submit("hi", :stub_ctx)
    end
  end

  def test_dispatch_slash_calls_registered_handler_with_args_and_ctx
    builder = Cclikesh::Builder.new
    captured = []
    builder.slash(:greet) { |args, ctx| captured << [args, ctx] }

    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_slash(:greet, ["alice"], :stub_ctx)

    assert_equal [[["alice"], :stub_ctx]], captured
  end

  def test_dispatch_slash_returns_not_registered_for_unknown
    builder = Cclikesh::Builder.new
    registry = Cclikesh::HandlerRegistry.new(builder)

    assert_equal :not_registered, registry.dispatch_slash(:unknown, [], :stub_ctx)
  end
end
