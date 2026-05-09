# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/input_box"
require "cclikesh/layout"

class TestInputBox < Test::Unit::TestCase
  class FakeTty < StringIO
    def tty?; true; end
  end

  def setup
    Cclikesh::Layout.recompute(rows: 24, cols: 20, header_height: 0, input_height: 3, footer_height: 0)
  end

  def test_height_is_three
    assert_equal 3, Cclikesh::InputBox.height
  end

  def test_prompt_starts_with_left_bar
    assert Cclikesh::InputBox.prompt.start_with?("│")
  end

  def test_paint_writes_top_and_bottom_borders_at_input_rows
    io = FakeTty.new
    Cclikesh::InputBox.paint(io, 20)
    s = io.string
    bar_w = 18
    assert s.include?("╭" + ("─" * bar_w) + "╮"), "expected top border, got: #{s.dump}"
    assert s.include?("╰" + ("─" * bar_w) + "╯"), "expected bottom border, got: #{s.dump}"
  end

  def test_paint_positions_at_input_top_and_input_bottom
    io = FakeTty.new
    Cclikesh::InputBox.paint(io, 20)
    s = io.string
    assert_match(/\e\[#{Cclikesh::Layout.input_top};1H/,    s)
    assert_match(/\e\[#{Cclikesh::Layout.input_bottom};1H/, s)
  end

  def test_paint_skips_when_io_is_not_tty
    io = StringIO.new
    Cclikesh::InputBox.paint(io, 20)
    assert_equal "", io.string
  end

  def test_paint_saves_and_restores_cursor
    io = FakeTty.new
    Cclikesh::InputBox.paint(io, 20)
    s = io.string
    assert s.include?("\e[s"), "expected save_cursor"
    assert s.include?("\e[u"), "expected restore_cursor"
  end

  def test_paint_handles_narrow_cols
    io = FakeTty.new
    Cclikesh::InputBox.paint(io, 4)
    s = io.string
    assert s.include?("╭──╮"), "narrow box must still produce a valid border, got: #{s.dump}"
    assert s.include?("╰──╯"), "narrow box must still produce a valid bottom border, got: #{s.dump}"
  end
end
