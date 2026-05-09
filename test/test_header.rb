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
    assert_equal 2, cfg.height
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
    assert_equal 4, cfg.height
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
end
