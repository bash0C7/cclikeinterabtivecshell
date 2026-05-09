# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/mouse"

class TestMouse < Test::Unit::TestCase
  def tty_io
    io = StringIO.new
    def io.tty?; true; end
    io
  end

  def test_enable_writes_combined_escape_codes_to_tty
    io = tty_io
    Cclikesh::Mouse.enable(io)
    assert io.string.include?("\e[?1000h"), "expected ?1000h in #{io.string.inspect}"
    assert io.string.include?("\e[?1003h"), "expected ?1003h"
    assert io.string.include?("\e[?1006h"), "expected ?1006h"
  end

  def test_disable_writes_combined_disable_codes
    io = tty_io
    Cclikesh::Mouse.disable(io)
    assert io.string.include?("\e[?1006l")
    assert io.string.include?("\e[?1003l")
    assert io.string.include?("\e[?1000l")
  end

  def test_enable_disable_noop_when_not_tty
    io = StringIO.new
    Cclikesh::Mouse.enable(io)
    Cclikesh::Mouse.disable(io)
    assert_equal "", io.string
  end

  def test_parse_left_press
    e = Cclikesh::Mouse.parse("\e[<0;10;5M")
    assert_equal :left, e.button
    assert_equal 10,    e.x
    assert_equal 5,     e.y
    assert_equal :press, e.type
  end

  def test_parse_right_release
    e = Cclikesh::Mouse.parse("\e[<2;33;7m")
    assert_equal :right,   e.button
    assert_equal 33,       e.x
    assert_equal 7,        e.y
    assert_equal :release, e.type
  end

  def test_parse_wheel_up
    e = Cclikesh::Mouse.parse("\e[<64;1;1M")
    assert_equal :wheel_up, e.button
    assert_equal :wheel,    e.type
  end

  def test_parse_wheel_down
    e = Cclikesh::Mouse.parse("\e[<65;1;1M")
    assert_equal :wheel_down, e.button
    assert_equal :wheel,      e.type
  end

  def test_parse_returns_nil_on_non_mouse_input
    assert_nil Cclikesh::Mouse.parse("hello")
    assert_nil Cclikesh::Mouse.parse("\e[A")
    assert_nil Cclikesh::Mouse.parse("")
    assert_nil Cclikesh::Mouse.parse(nil)
  end

  def test_osc52_copy_writes_base64_with_paste_terminator
    io = tty_io
    Cclikesh::Mouse.osc52_copy(io, "hello")
    # base64("hello") = "aGVsbG8="
    assert_match(/\e\]52;c;aGVsbG8=\a/, io.string)
  end

  def test_osc52_copy_noop_when_not_tty
    io = StringIO.new
    Cclikesh::Mouse.osc52_copy(io, "x")
    assert_equal "", io.string
  end
end
