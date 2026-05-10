require_relative "test_helper"
require "curses"
require "cclikesh/style"
require "cclikesh/chrome"

class TestChrome < Test::Unit::TestCase
  def setup
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
    Cclikesh::Chrome.init
  end

  def teardown
    Cclikesh::Chrome.close
    Curses.close_screen
  rescue
    nil
  end

  def test_header_lines_appear_in_header_window
    Cclikesh::Chrome.update_header(["✻ cclikesh", "  v0.2.0"])
    # inch returns narrow-char bytes only, so non-ASCII chars may be truncated;
    # match on the ASCII portion that reliably survives the inch encoding
    cells = capture_window_text(Cclikesh::Chrome.header_win, 0, 0, 12)
    assert_match(/cclikesh/, cells)
  end

  def test_footer_includes_shortcuts_hint
    Cclikesh::Chrome.update_footer(info_bar: [], status_rows: [], shortcuts_hint: "? for shortcuts")
    cells = capture_window_text(Cclikesh::Chrome.footer_win, 2, 0, 16)
    assert_match(/\? for shortcuts/, cells)
  end

  def test_tick_spinner_advances_index_when_phase_working
    initial = Cclikesh::Chrome.spinner_index
    Cclikesh::Chrome.tick_spinner(:working)
    assert_not_equal initial, Cclikesh::Chrome.spinner_index
  end

  def test_tick_spinner_noop_when_idle
    initial = Cclikesh::Chrome.spinner_index
    Cclikesh::Chrome.tick_spinner(:idle)
    assert_equal initial, Cclikesh::Chrome.spinner_index
  end

  def test_truncate_to_width_handles_cjk
    s = "日本語abc"  # widths: 2+2+2+1+1+1 = 9
    truncated = Cclikesh::Chrome.truncate_to_width(s, 5)
    require "unicode/display_width"
    assert Unicode::DisplayWidth.of(truncated) <= 5
    assert truncated.end_with?("…")
  end

  def test_truncate_returns_unchanged_when_under_limit
    assert_equal "短い", Cclikesh::Chrome.truncate_to_width("短い", 10)
  end

  private

  def capture_window_text(win, row, col, len)
    chars = []
    len.times do |i|
      win.setpos(row, col + i)
      ch = win.inch & Curses::A_CHARTEXT
      begin
        chars << ch.chr(Encoding::UTF_8)
      rescue
        chars << "?"
      end
    end
    chars.join
  end
end
