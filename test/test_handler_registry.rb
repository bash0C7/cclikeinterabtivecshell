# frozen_string_literal: true

require "stringio"
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

  def test_style_definition_returns_builder_value
    b = Cclikesh::Builder.new
    b.define_style(:hi, fg: :magenta)
    r = Cclikesh::HandlerRegistry.new(b)
    assert_equal({ fg: :magenta }, r.style_definition(:hi))
  end

  def test_style_definition_unknown_returns_nil
    b = Cclikesh::Builder.new
    r = Cclikesh::HandlerRegistry.new(b)
    assert_nil r.style_definition(:none)
  end

  def test_registry_exposes_builder_logger
    io = StringIO.new
    builder = Cclikesh::Builder.new
    builder.log_to(io)
    builder.log_level = :debug
    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.logger.info("from-impl")
    assert_match(/from-impl/, io.string)
  end

  def test_dispatch_state_change_calls_handler
    builder = Cclikesh::Builder.new
    recorded = []
    builder.on_state_change { |k, o, n, ctx| recorded << [k, o, n, ctx] }
    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_state_change(:phase, nil, :working, :ctx_sentinel)
    assert_equal [[:phase, nil, :working, :ctx_sentinel]], recorded
  end

  def test_dispatch_state_change_no_handler_is_noop
    builder = Cclikesh::Builder.new
    registry = Cclikesh::HandlerRegistry.new(builder)
    assert_nothing_raised do
      registry.dispatch_state_change(:phase, nil, :working, :ctx)
    end
  end

  def test_dispatch_state_change_logs_handler_error
    io = StringIO.new
    builder = Cclikesh::Builder.new
    builder.log_to(io)
    builder.on_state_change { |_, _, _, _| raise "state-change-boom" }
    registry = Cclikesh::HandlerRegistry.new(builder)
    assert_nothing_raised { registry.dispatch_state_change(:k, 1, 2, :ctx) }
    assert_match(/state-change-boom/, io.string)
  end

  def test_dispatch_start_runs_each_in_registration_order
    builder = Cclikesh::Builder.new
    seq = []
    builder.on_start { |_| seq << :first }
    builder.on_start { |_| seq << :second }
    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_start(:ctx)
    assert_equal [:first, :second], seq
  end

  def test_dispatch_start_logs_and_continues_on_error
    io = StringIO.new
    builder = Cclikesh::Builder.new
    builder.log_to(io)
    seq = []
    builder.on_start { |_| raise "boom" }
    builder.on_start { |_| seq << :ran }
    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_start(:ctx)
    assert_equal [:ran], seq
    assert_match(/boom/, io.string)
  end

  def test_dispatch_quit_runs_in_reverse_order
    builder = Cclikesh::Builder.new
    seq = []
    builder.on_quit { |_| seq << :first }
    builder.on_quit { |_| seq << :second }
    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_quit(:ctx)
    assert_equal [:second, :first], seq
  end

  def test_dispatch_quit_logs_and_continues_on_error
    io = StringIO.new
    builder = Cclikesh::Builder.new
    builder.log_to(io)
    seq = []
    builder.on_quit { |_| seq << :ran }
    builder.on_quit { |_| raise "quit-boom" }
    registry = Cclikesh::HandlerRegistry.new(builder)
    registry.dispatch_quit(:ctx)
    assert_equal [:ran], seq
    assert_match(/quit-boom/, io.string)
  end
end
