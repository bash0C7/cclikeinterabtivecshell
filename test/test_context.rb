# frozen_string_literal: true

require "stringio"
require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/context"
require "cclikesh/builder"
require "cclikesh/handler_registry"

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

  def test_context_logger_returns_registry_logger
    ts = Cclikesh::TupleSpace.new
    io = StringIO.new
    builder = Cclikesh::Builder.new
    builder.log_to(io)
    registry = Cclikesh::HandlerRegistry.new(builder)
    ctx = Cclikesh::Context.new(ts, registry: registry)
    ctx.logger.info("through-ctx")
    assert_match(/through-ctx/, io.string)
  end

  def test_context_logger_returns_nil_when_no_registry
    ts = Cclikesh::TupleSpace.new
    ctx = Cclikesh::Context.new(ts)
    assert_nil ctx.logger
  end
end
