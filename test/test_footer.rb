# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/footer"

class TestFooter < Test::Unit::TestCase
  def setup
    Cclikesh::Layout.recompute(rows: 24, cols: 80, header_height: 0, input_height: 1, footer_height: 2)
  end

  def test_row_text_appends_segment
    row = Cclikesh::Footer::Row.new
    row.text("hello")
    assert_equal ["hello"], row.segments
    assert_equal "hello", row.to_line
  end

  def test_row_text_with_style
    row = Cclikesh::Footer::Row.new
    row.text("hi", style: :result)
    assert_equal "\e[32mhi\e[0m", row.segments.first
  end

  def test_row_bar_renders_unicode_bar_with_percent
    row = Cclikesh::Footer::Row.new
    row.bar(percent: 50, width: 4)
    assert_equal "██░░ 50%", row.segments.first
  end

  def test_row_bar_clamps_below_zero
    row = Cclikesh::Footer::Row.new
    row.bar(percent: -10, width: 4)
    assert_equal "░░░░ 0%", row.segments.first
  end

  def test_row_bar_clamps_above_hundred
    row = Cclikesh::Footer::Row.new
    row.bar(percent: 150, width: 4)
    assert_equal "████ 100%", row.segments.first
  end

  def test_row_link_renders_underlined_with_state_color
    row = Cclikesh::Footer::Row.new
    row.link(text: "PR #42", state: :green)
    assert_equal "\e[32;4mPR #42\e[0m", row.segments.first
  end

  def test_row_link_unknown_state_falls_back_to_gray
    row = Cclikesh::Footer::Row.new
    row.link(text: "X", state: :unknown_xyz)
    assert_equal "\e[90;4mX\e[0m", row.segments.first
  end

  def test_row_to_line_joins_with_dot_separator
    row = Cclikesh::Footer::Row.new
    row.text("a")
    row.text("b")
    row.text("c")
    assert_equal "a · b · c", row.to_line
  end

  def test_row_chainable
    row = Cclikesh::Footer::Row.new
    result = row.text("a").bar(percent: 0, width: 2).icon(":")
    assert_same row, result
    assert_equal 3, row.segments.size
  end

  def test_paint_writes_lines_at_footer_rows
    io = StringIO.new
    Cclikesh::Layout.recompute(rows: 24, cols: 80, header_height: 0, input_height: 1, footer_height: 2)
    # rows=24, input=1, footer=2 → input=row 22, footer rows=23 and 24
    Cclikesh::Footer.paint(io, ["row0", "row1"])
    assert_match(/\e\[23;1H\e\[2Krow0/, io.string)
    assert_match(/\e\[24;1H\e\[2Krow1/, io.string)
  end

  def test_paint_with_nil_or_empty_writes_nothing
    io = StringIO.new
    Cclikesh::Footer.paint(io, nil)
    Cclikesh::Footer.paint(io, [])
    assert_equal "", io.string
  end

  def test_paint_skips_nil_line
    io = StringIO.new
    Cclikesh::Footer.paint(io, ["only"])
    assert_match(/\e\[2Konly/, io.string)
  end
end
