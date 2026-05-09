# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/header"

class TestHeader < Test::Unit::TestCase
  def setup
    Cclikesh::Layout.recompute(rows: 24, cols: 80, header_height: 0, input_height: 1, footer_height: 0)
  end

  def test_configurator_with_no_attrs_has_no_lines
    cfg = Cclikesh::Header::Configurator.new
    assert_equal [], cfg.lines
    assert_equal 0,  cfg.height
  end

  def test_configurator_title_only_renders_one_line
    cfg = Cclikesh::Header::Configurator.new
    cfg.title = "myshell"
    assert_equal ["myshell"], cfg.lines
    assert_equal 4, cfg.height
  end

  def test_configurator_logo_and_title_combined
    cfg = Cclikesh::Header::Configurator.new
    cfg.logo  = "✻"
    cfg.title = "cclikesh"
    cfg.version = "v0.1.0"
    assert_equal ["✻  cclikesh v0.1.0"], cfg.lines
  end

  def test_configurator_full_three_line_layout
    cfg = Cclikesh::Header::Configurator.new
    cfg.logo  = "✻"
    cfg.title = "cclikesh"
    cfg.version = "v0.1.0"
    cfg.subtitle = "Ruby 4.0"
    cfg.note     = "/q to exit"
    assert_equal [
      "✻  cclikesh v0.1.0",
      "   Ruby 4.0",
      "   /q to exit"
    ], cfg.lines
    assert_equal 6, cfg.height
  end

  def test_configurator_logo_only
    cfg = Cclikesh::Header::Configurator.new
    cfg.logo = "✻"
    assert_equal ["✻"], cfg.lines
  end

  def test_paint_writes_each_line_at_its_row
    io = StringIO.new
    Cclikesh::Header.paint(io, ["one", "two", "three"])
    assert_match(/\e\[1;1H\e\[2Kone/,   io.string)
    assert_match(/\e\[2;1H\e\[2Ktwo/,   io.string)
    assert_match(/\e\[3;1H\e\[2Kthree/, io.string)
    assert_match(/\e\[4;1H\e\[2K/,      io.string)
  end

  def test_paint_with_empty_lines_writes_nothing
    io = StringIO.new
    Cclikesh::Header.paint(io, [])
    assert_equal "", io.string
    Cclikesh::Header.paint(io, nil)
    assert_equal "", io.string
  end

  def test_box_wraps_content_in_corners
    boxed = Cclikesh::Header.box(["hello"], 20)
    assert_equal "╭" + ("─" * 18) + "╮", boxed.first
    assert_equal "╰" + ("─" * 18) + "╯", boxed.last
    assert_equal "│ hello#{" " * 11} │", boxed[1]
    assert_equal 3, boxed.size
  end

  def test_box_with_empty_content_returns_empty
    assert_equal [], Cclikesh::Header.box([], 80)
    assert_equal [], Cclikesh::Header.box(nil, 80)
  end

  def test_box_pads_each_line_to_inner_width
    boxed = Cclikesh::Header.box(["a", "bb", "ccc"], 12)
    boxed[1..-2].each do |row|
      assert row.start_with?("│ "), "expected left bar, got: #{row.inspect}"
      assert row.end_with?(" │"),   "expected right bar, got: #{row.inspect}"
      assert_equal 12, row.length, "expected width 12, got #{row.length}: #{row.inspect}"
    end
  end

  def test_paint_with_cols_renders_boxed_form
    io = StringIO.new
    Cclikesh::Header.paint(io, ["hi"], cols: 10)
    assert_match(/╭─{8}╮/,         io.string)
    assert_match(/│ hi#{" " * 4} │/, io.string)
    assert_match(/╰─{8}╯/,         io.string)
  end
end
