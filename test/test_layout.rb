# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/layout"

class TestLayout < Test::Unit::TestCase
  def setup
    Cclikesh::Layout.recompute(
      rows: 24, cols: 80,
      header_height: 0, input_height: 1, footer_height: 0
    )
  end

  def test_default_layout_24x80_no_header_no_footer
    Cclikesh::Layout.recompute(rows: 24, cols: 80, header_height: 0, input_height: 1, footer_height: 0)
    assert_equal 1,  Cclikesh::Layout.history_top
    assert_equal 23, Cclikesh::Layout.history_bottom
    assert_equal 24, Cclikesh::Layout.input_top
    assert_equal 24, Cclikesh::Layout.input_bottom
  end

  def test_layout_with_header_and_footer
    Cclikesh::Layout.recompute(rows: 30, cols: 100, header_height: 3, input_height: 1, footer_height: 2)
    assert_equal 1,  Cclikesh::Layout.header_top
    assert_equal 3,  Cclikesh::Layout.header_bottom
    assert_equal 4,  Cclikesh::Layout.history_top
    assert_equal 27, Cclikesh::Layout.history_bottom
    assert_equal 28, Cclikesh::Layout.input_top
    assert_equal 28, Cclikesh::Layout.input_bottom
    assert_equal 29, Cclikesh::Layout.footer_top
    assert_equal 30, Cclikesh::Layout.footer_bottom
  end

  def test_layout_with_multi_row_input
    Cclikesh::Layout.recompute(rows: 24, cols: 80, header_height: 2, input_height: 3, footer_height: 1)
    assert_equal 20, Cclikesh::Layout.history_bottom
    assert_equal 21, Cclikesh::Layout.input_top
    assert_equal 23, Cclikesh::Layout.input_bottom
    assert_equal 24, Cclikesh::Layout.footer_top
  end

  def test_position_writes_cursor_escape
    io = StringIO.new
    Cclikesh::Layout.position(io, 5, 3)
    assert_equal "\e[5;3H", io.string
  end

  def test_set_scroll_region_writes_decstbm_with_history_range
    Cclikesh::Layout.recompute(rows: 24, cols: 80, header_height: 2, input_height: 1, footer_height: 1)
    io = StringIO.new
    Cclikesh::Layout.set_scroll_region(io)
    assert_equal "\e[3;22r", io.string
  end

  def test_reset_scroll_region_writes_full_screen_decstbm
    io = StringIO.new
    Cclikesh::Layout.reset_scroll_region(io)
    assert_equal "\e[r", io.string
  end

  def tty_io
    io = StringIO.new
    def io.tty?; true; end
    io
  end

  def test_in_history_brackets_with_save_position_restore
    Cclikesh::Layout.recompute(rows: 24, cols: 80, header_height: 0, input_height: 1, footer_height: 0)
    io = tty_io
    Cclikesh::Layout.in_history(io) { io.write("HELLO") }
    assert_equal "\e[s\e[23;1HHELLO\e[u", io.string
  end

  def test_in_history_restores_cursor_even_on_exception
    io = tty_io
    assert_raises(RuntimeError) do
      Cclikesh::Layout.in_history(io) { raise "boom" }
    end
    assert io.string.end_with?("\e[u"), "expected cursor restore in #{io.string.inspect}"
  end

  def test_in_history_passthrough_when_io_not_tty
    io = StringIO.new
    Cclikesh::Layout.in_history(io) { io.write("HELLO") }
    assert_equal "HELLO", io.string
  end

  def test_history_bottom_never_overlaps_history_top_when_terminal_too_small
    Cclikesh::Layout.recompute(rows: 4, cols: 80, header_height: 3, input_height: 1, footer_height: 1)
    assert_operator Cclikesh::Layout.history_bottom, :>=, Cclikesh::Layout.history_top
  end
end
