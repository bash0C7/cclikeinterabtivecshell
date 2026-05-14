require_relative "test_helper"
require "curses"

class TestCursesIntegration < Test::Unit::TestCase
  def setup
    Curses.init_screen
    Curses.start_color
  end

  def teardown
    Curses.close_screen
  rescue
    nil
  end

  def test_init_screen_close_screen_round_trip
    win = Curses::Window.new(1, 10, 0, 0)
    win.addstr("hello")
    win.refresh
    win.setpos(0, 0)
    captured = win.inch & Curses::A_CHARTEXT
    assert_equal "h".ord, captured
    win.close
  end

  def test_color_pair_init
    Curses.use_default_colors
    Curses.init_pair(1, Curses::COLOR_GREEN, -1)
    pair = Curses.color_pair(1)
    assert pair > 0
  end

  def test_pad_creation_and_close
    pad = Curses::Pad.new(100, 80)
    pad.addstr("padded text")
    pad.close
    assert true  # if we got here, it worked
  end

  def test_setpos_and_addstr_interaction
    win = Curses::Window.new(5, 20, 0, 0)
    win.setpos(0, 0)
    win.addstr("line1")
    win.setpos(1, 0)
    win.addstr("line2")
    win.setpos(0, 0)
    # Read back the first character
    ch = win.inch & Curses::A_CHARTEXT
    assert_equal "l".ord, ch
    win.close
  end

  def test_window_clear_and_refresh
    win = Curses::Window.new(3, 15, 0, 0)
    win.addstr("test")
    win.refresh
    win.clear
    win.refresh
    win.close
    assert true
  end
end
