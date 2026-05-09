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

  def test_quit_writes_only_nil_key_not_cmd_quit
    ts = Cclikesh::TupleSpace.new
    ctx = Cclikesh::Context.new(ts)
    ctx.quit

    # nil key signals dispatcher
    key_tuple = ts.take([:key, nil], 1)
    assert_equal [:key, nil], key_tuple

    # NO cmd/quit tuple should be present
    assert_raise(Rinda::RequestExpiredError) do
      ts.take([:cmd, :quit], 0)
    end
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

  def test_context_logger_raises_when_no_registry
    ts = Cclikesh::TupleSpace.new
    ctx = Cclikesh::Context.new(ts)
    assert_raise(RuntimeError) { ctx.logger }
  end

  def test_refresh_writes_refresh_command_tuple
    ts = Cclikesh::TupleSpace.new
    ctx = Cclikesh::Context.new(ts)
    ctx.refresh
    tuple = ts.take([:cmd, :refresh], 1)
    assert_equal [:cmd, :refresh], tuple
  end

  def test_context_dialog_returns_dialog_instance
    ts = Cclikesh::TupleSpace.new
    ctx = Cclikesh::Context.new(ts)
    assert_kind_of Cclikesh::Dialog, ctx.dialog
  end

  def test_context_dialog_writes_through_display
    ts = Cclikesh::TupleSpace.new
    ctx = Cclikesh::Context.new(ts)
    ctx.dialog.show("hi")

    found = []
    begin
      loop { found << ts.take([:render, :display_append, nil, nil], 0) }
    rescue Rinda::RequestExpiredError
      # done
    end
    matched = found.any? { |t| t[2].include?("hi") }
    assert(matched, "dialog content not pushed to display: #{found.inspect}")
  end
end
