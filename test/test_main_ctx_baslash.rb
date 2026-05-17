# frozen_string_literal: true

require_relative "test_helper"
require "baslash/context"
require "baslash/main_ctx"

class TestMainCtxBaslash < Test::Unit::TestCase
  def setup
    Baslash::Context.init(logger: Logger.new(IO::NULL))
  end

  def teardown
    Baslash::Context.reset!
  end

  def test_state_reads_from_context
    Baslash::Context.state_set(:last_status, 42)
    ctx = Baslash::MainCtx.new
    assert_equal 42, ctx.state[:last_status]
  end

  def test_state_string_key
    Baslash::Context.state_set(:phase, :working)
    ctx = Baslash::MainCtx.new
    assert_equal :working, ctx.state["phase"]
  end

  def test_state_missing_key_returns_nil
    ctx = Baslash::MainCtx.new
    assert_nil ctx.state[:never_set]
  end
end
