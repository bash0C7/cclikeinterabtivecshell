# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh"

class TestMainCtx < Test::Unit::TestCase
  def setup
    Cclikesh::Context.init(logger: Logger.new(IO::NULL))
  end

  def teardown
    Cclikesh::Context.reset!
  end

  def test_shareable_returns_ref_by_symbol
    fake_ref = Object.new
    ctx = Cclikesh::MainCtx.new({ cwd: fake_ref })
    assert_same fake_ref, ctx.shareable(:cwd)
  end

  def test_shareable_accepts_string_name
    fake_ref = Object.new
    ctx = Cclikesh::MainCtx.new({ env: fake_ref })
    assert_same fake_ref, ctx.shareable("env")
  end

  def test_shareable_unknown_name_raises
    ctx = Cclikesh::MainCtx.new({})
    assert_raise(RuntimeError) { ctx.shareable(:nope) }
  end

  def test_state_reads_from_context
    Cclikesh::Context.state_set(:last_status, 42)
    ctx = Cclikesh::MainCtx.new({})
    assert_equal 42, ctx.state[:last_status]
  end

  def test_state_string_key
    Cclikesh::Context.state_set(:phase, :working)
    ctx = Cclikesh::MainCtx.new({})
    assert_equal :working, ctx.state["phase"]
  end

  def test_state_missing_key_returns_nil
    ctx = Cclikesh::MainCtx.new({})
    assert_nil ctx.state[:never_set]
  end
end
