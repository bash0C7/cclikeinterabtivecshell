# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/builder"

class TestBuilder < Test::Unit::TestCase
  def test_on_submit_stores_block
    b = Cclikesh::Builder.new
    block = proc { |line, ctx| line.upcase }
    b.on_submit(&block)
    assert_same block, b.on_submit_handler
  end

  def test_on_submit_called_twice_replaces
    b = Cclikesh::Builder.new
    b.on_submit { |line, ctx| 1 }
    second = proc { |line, ctx| 2 }
    b.on_submit(&second)
    assert_same second, b.on_submit_handler
  end

  def test_slash_stores_per_name_handler
    b = Cclikesh::Builder.new
    quit_block = proc { |args, ctx| ctx.quit }
    b.slash(:quit, &quit_block)
    assert_same quit_block, b.slash_handler(:quit)
  end

  def test_slash_handler_unknown_returns_nil
    b = Cclikesh::Builder.new
    assert_nil b.slash_handler(:nope)
  end

  def test_slash_accepts_string_name_normalized_to_symbol
    b = Cclikesh::Builder.new
    block = proc { |args, ctx| nil }
    b.slash("quit", &block)
    assert_same block, b.slash_handler(:quit)
  end
end
