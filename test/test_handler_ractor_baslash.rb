# frozen_string_literal: true

require "timeout"
require_relative "test_helper"
require "baslash/handler_ractor"
require "baslash/ctx_proxy"

class TestHandlerRactorBaslash < Test::Unit::TestCase
  def test_spawn_runs_body_with_args
    body = Ractor.shareable_proc { |args, ctx| ctx.display.append("got: #{args.first}") }
    main = Ractor.current
    bp = Baslash::CtxProxy.blueprint(main, {})
    Baslash::HandlerRactor.spawn(body: body, args: ["hello"].freeze, ctx_blueprint: bp)
    msg = Timeout.timeout(2.0) { Ractor.receive }
    assert_equal :append, msg[0]
    assert_equal "got: hello", msg[1]
  end

  def test_handler_exception_sends_error_log
    body = Ractor.shareable_proc { |args, ctx| raise "boom" }
    main = Ractor.current
    bp = Baslash::CtxProxy.blueprint(main, {})
    Baslash::HandlerRactor.spawn(body: body, args: [].freeze, ctx_blueprint: bp)
    # Drain messages with a deadline until we see logger:error
    msgs = []
    Timeout.timeout(2.0) do
      loop do
        msgs << Ractor.receive
        break if msgs.any? { |m| m[0] == :logger && m[1] == :error }
      end
    end
    assert msgs.any? { |m| m[0] == :logger && m[1] == :error }, "expected :logger error msg, got #{msgs.inspect}"
  end
end
