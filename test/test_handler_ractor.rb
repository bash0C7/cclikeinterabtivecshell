# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/handler_ractor"
require "cclikesh/ctx_proxy"

class TestHandlerRactor < Test::Unit::TestCase
  def test_spawn_runs_body_with_args
    body = Ractor.shareable_proc { |args, ctx| ctx.display.append("got: #{args.first}") }
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Cclikesh::HandlerRactor.spawn(body: body, args: ["hello"].freeze, ctx_blueprint: bp)
    msg = Ractor.receive
    assert_equal :append, msg[0]
    assert_equal "got: hello", msg[1]
  end

  def test_handler_exception_sends_error_log
    body = Ractor.shareable_proc { |args, ctx| raise "boom" }
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Cclikesh::HandlerRactor.spawn(body: body, args: [].freeze, ctx_blueprint: bp)
    # Drain messages until we see logger:error
    msgs = []
    5.times do
      begin
        msgs << Ractor.receive
      rescue Ractor::ClosedError
        break
      end
    end
    assert msgs.any? { |m| m[0] == :logger && m[1] == :error }, "expected :logger error msg, got #{msgs.inspect}"
  end
end
