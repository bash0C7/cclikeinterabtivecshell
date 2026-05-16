# frozen_string_literal: true

require_relative "test_helper"
require "baslash/ctx_proxy"

class TestCtxProxyBaslash < Test::Unit::TestCase
  def test_display_append_sends_command_to_main
    main = Ractor.current
    bp = Baslash::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Baslash::CtxProxy.from_blueprint(b)
      ctx.display.append("hello", style: :result)
    end
    msg = Ractor.receive
    assert_equal :append, msg[0]
    assert_equal "hello", msg[1]
    assert_equal({ style: :result }, msg[2])
  end

  def test_state_set_sends_state_set
    main = Ractor.current
    bp = Baslash::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Baslash::CtxProxy.from_blueprint(b)
      ctx.state[:phase] = :working
    end
    msg = Ractor.receive
    assert_equal :state_set, msg[0]
    assert_equal :phase,     msg[1]
    assert_equal :working,   msg[2]
  end

  def test_logger_error_sends_logger
    main = Ractor.current
    bp = Baslash::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Baslash::CtxProxy.from_blueprint(b)
      ctx.logger.error("boom")
    end
    msg = Ractor.receive
    assert_equal :logger, msg[0]
    assert_equal :error,  msg[1]
    assert_equal "boom",  msg[2]
  end

  def test_quit_sends_quit
    main = Ractor.current
    bp = Baslash::CtxProxy.blueprint(main, {})
    # ctx.quit sends SIGINT to wake up Reline in production; absorb it here.
    old_trap = Signal.trap("INT") { nil }
    r = Ractor.new(bp) do |b|
      ctx = Baslash::CtxProxy.from_blueprint(b)
      ctx.quit
    end
    msg = Ractor.receive
    r.join rescue nil  # wait for ractor to finish so SIGINT is fully delivered
    sleep 0.05         # let any pending signal fire under the absorb trap
    assert_equal [:quit], msg
  ensure
    Signal.trap("INT", old_trap || "DEFAULT")
  end

  def test_shareable_returns_named_ref
    require "baslash/shareable_ref"
    refs = { evaluator: Baslash::ShareableRef.spawn(:evaluator) { Object.new } }
    main = Ractor.current
    bp = Baslash::CtxProxy.blueprint(main, refs)
    Ractor.new(main, bp) do |m, b|
      ctx = Baslash::CtxProxy.from_blueprint(b)
      ref = ctx.shareable(:evaluator)
      m.send([:ref_name, ref.name])
    end
    msg = Ractor.receive
    assert_equal :ref_name,  msg[0]
    assert_equal :evaluator, msg[1]
  ensure
    refs[:evaluator]&.stop
  end
end
