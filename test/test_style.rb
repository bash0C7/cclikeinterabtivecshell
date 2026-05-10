# frozen_string_literal: true

require_relative "test_helper"
require "curses"
require "cclikesh/style"

class TestStyle < Test::Unit::TestCase
  def setup
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
  end

  def teardown
    Curses.close_screen
  rescue
    nil
  end

  def test_builtin_result_returns_color_pair_and_attr
    pair, attr = Cclikesh::Style.lookup(:result)
    refute_nil pair
    assert_equal 0, attr
  end

  def test_builtin_dim_returns_a_dim_attr
    pair, attr = Cclikesh::Style.lookup(:dim)
    assert (attr & Curses::A_DIM) != 0
  end

  def test_define_custom_style
    Cclikesh::Style.define(:warn, fg: Curses::COLOR_YELLOW, bold: true)
    pair, attr = Cclikesh::Style.lookup(:warn)
    refute_nil pair
    assert (attr & Curses::A_BOLD) != 0
  end

  def test_unknown_style_returns_nil
    assert_equal [nil, 0], Cclikesh::Style.lookup(:nope)
  end

  def test_with_yields_then_attroff
    win = Curses::Window.new(1, 10, 0, 0)
    captured = nil
    Cclikesh::Style.with(win, :result) { captured = :inside }
    assert_equal :inside, captured
    win.close
  end
end
