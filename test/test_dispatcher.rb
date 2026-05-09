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

  def test_bang_payload_runs_shell_command_and_appends_output
    @ts.write([:key, "!echo hello-from-shell"])

    @dispatcher.dispatch_one

    # tag line first
    @ts.take([:render, :display_append, "$ echo hello-from-shell", nil], 1)
    # output line (with indent prefix from begin_indent_block)
    out_tuple = @ts.take([:render, :display_append, "  └ hello-from-shell", nil], 1)
    assert_equal :display_append, out_tuple[1]
  end

  def test_bang_payload_with_empty_command_is_noop
    @ts.write([:key, "!   "])

    assert_nothing_raised { @dispatcher.dispatch_one }
    assert_raises(Rinda::RequestExpiredError) do
      @ts.take([:render, :display_append, nil, nil], 0)
    end
  end

  def test_bang_payload_with_failing_command_logs_exit_status
    @ts.write([:key, "!ruby -e 'exit 7'"])

    @dispatcher.dispatch_one

    @ts.take([:render, :display_append, "$ ruby -e 'exit 7'", nil], 1)
    @ts.take([:render, :display_append, "  └ (exit 7)", nil], 1)
  end
end
