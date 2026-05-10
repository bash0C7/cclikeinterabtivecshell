# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/ctx_proxy"

class TestCtxProxy < Test::Unit::TestCase
  def test_display_append_sends_command_to_main
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      ctx.display.append("hello", style: :result)
    end
    msg = Ractor.receive
    assert_equal :append, msg[0]
    assert_equal "hello", msg[1]
    assert_equal({ style: :result }, msg[2])
  end

  def test_state_set_sends_state_set
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      ctx.state[:phase] = :working
    end
    msg = Ractor.receive
    assert_equal :state_set, msg[0]
    assert_equal :phase,     msg[1]
    assert_equal :working,   msg[2]
  end

  def test_logger_error_sends_logger
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      ctx.logger.error("boom")
    end
    msg = Ractor.receive
    assert_equal :logger, msg[0]
    assert_equal :error,  msg[1]
    assert_equal "boom",  msg[2]
  end

  def test_quit_sends_quit
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, {})
    Ractor.new(bp) do |b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
      ctx.quit
    end
    msg = Ractor.receive
    assert_equal [:quit], msg
  end

  def test_shareable_returns_named_ref
    require "cclikesh/shareable_ref"
    refs = { evaluator: Cclikesh::ShareableRef.spawn(:evaluator) { Object.new } }
    main = Ractor.current
    bp = Cclikesh::CtxProxy.blueprint(main, refs)
    Ractor.new(main, bp) do |m, b|
      ctx = Cclikesh::CtxProxy.from_blueprint(b)
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
