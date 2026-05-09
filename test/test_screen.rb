# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/screen"

class TestScreen < Test::Unit::TestCase
  def tty_io
    io = StringIO.new
    def io.tty?; true; end
    io
  end

  def test_enter_alt_writes_escape_to_tty
    io = tty_io
    Cclikesh::Screen.enter_alt(io)
    assert_equal "\e[?1049h\e[H", io.string
  end

  def test_leave_alt_writes_escape_to_tty
    io = tty_io
    Cclikesh::Screen.leave_alt(io)
    assert_equal "\e[?1049l", io.string
  end

  def test_enter_alt_noop_when_not_tty
    io = StringIO.new
    Cclikesh::Screen.enter_alt(io)
    assert_equal "", io.string
  end

  def test_leave_alt_noop_when_not_tty
    io = StringIO.new
    Cclikesh::Screen.leave_alt(io)
    assert_equal "", io.string
  end

  def test_size_returns_default_when_not_tty
    io = StringIO.new
    assert_equal [24, 80], Cclikesh::Screen.size(io)
  end
end
