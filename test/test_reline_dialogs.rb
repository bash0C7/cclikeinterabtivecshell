# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/reline_dialogs"

class TestRelineDialogs < Test::Unit::TestCase
  def test_format_slash_line_without_description_is_just_name
    line = Cclikesh::RelineDialogs.format_slash_line(name: "/q", description: "")
    assert_equal "/q", line
  end

  def test_format_slash_line_pads_name_then_appends_dim_description
    line = Cclikesh::RelineDialogs.format_slash_line(name: "/reset", description: "reset irb session")
    assert_match(/\A\/reset +\e\[2;90mreset irb session\e\[0m\z/, line)
  end

  def test_format_slash_line_short_name_pads_to_width
    line = Cclikesh::RelineDialogs.format_slash_line(name: "/q", description: "exit")
    visible = line.gsub(/\e\[[0-9;]*m/, "")
    assert visible.start_with?("/q "), "expected padding after name, got #{visible.inspect}"
    assert visible.end_with?("exit"), "expected description at end, got #{visible.inspect}"
    assert visible.length >= 16, "expected total visible width >= 16, got #{visible.inspect}"
  end

  def test_format_slash_lines_maps_each_item
    items = [
      { name: "/q", description: "exit" },
      { name: "/reset", description: "reset session" }
    ]
    lines = Cclikesh::RelineDialogs.format_slash_lines(items)
    assert_equal 2, lines.size
    assert lines[0].include?("/q")
    assert lines[1].include?("/reset")
  end

  def test_visible_width_strips_ansi
    s = "\e[2;90mfoo\e[0m"
    assert_equal 3, Cclikesh::RelineDialogs.visible_width(s)
  end

  def test_visible_width_handles_plain_text
    assert_equal 5, Cclikesh::RelineDialogs.visible_width("hello")
  end

  def test_dialog_width_returns_max_visible_width
    lines = ["abc", "\e[2mlonger here\e[0m"]
    assert_equal "longer here".bytesize, Cclikesh::RelineDialogs.dialog_width(lines)
  end

  def test_dialog_width_for_empty_array
    assert_equal 0, Cclikesh::RelineDialogs.dialog_width([])
  end

  def test_format_ghost_hint_wraps_in_dim_gray
    s = Cclikesh::RelineDialogs.format_ghost_hint("type something")
    assert_equal "\e[2;90mtype something\e[0m", s
  end

  def test_format_ghost_hint_returns_nil_for_empty
    assert_nil Cclikesh::RelineDialogs.format_ghost_hint("")
    assert_nil Cclikesh::RelineDialogs.format_ghost_hint(nil)
  end
end
