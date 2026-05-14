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

  def test_footer_includes_shortcuts_hint
    Cclikesh::Chrome.update_footer(info_bar: [], status_rows: [], shortcuts_hint: "? for shortcuts")
    cells = capture_window_text(Cclikesh::Chrome.footer_win, 2, 0, 16)
    assert_match(/\? for shortcuts/, cells)
  end

  def test_tick_spinner_sets_start_time_on_working
    Cclikesh::Chrome.tick_spinner(:idle)
    assert_nil Cclikesh::Chrome.spinner_started_at
    Cclikesh::Chrome.tick_spinner(:working)
    assert_not_nil Cclikesh::Chrome.spinner_started_at
  end

  def test_tick_spinner_clears_start_time_on_idle
    Cclikesh::Chrome.tick_spinner(:working)
    assert_not_nil Cclikesh::Chrome.spinner_started_at
    Cclikesh::Chrome.tick_spinner(:idle)
    assert_nil Cclikesh::Chrome.spinner_started_at
  end

  def test_spinner_glyph_returns_first_glyph_when_idle
    Cclikesh::Chrome.tick_spinner(:idle)
    assert_equal Cclikesh::Chrome::SPINNER_GLYPHS.first, Cclikesh::Chrome.spinner_glyph(:idle)
  end

  def test_spinner_glyph_advances_with_elapsed_time_when_working
    Cclikesh::Chrome.tick_spinner(:idle)
    Cclikesh::Chrome.tick_spinner(:working)
    glyph_at_start = Cclikesh::Chrome.spinner_glyph(:working)
    # Advance @spinner_started_at backwards by 5 frames so spinner_glyph
    # computes a different index without sleeping.
    frames = 5
    Cclikesh::Chrome.instance_variable_set(
      :@spinner_started_at,
      Time.now - (Cclikesh::Chrome::SPINNER_FRAME_MS * frames / 1000.0)
    )
    glyph_after = Cclikesh::Chrome.spinner_glyph(:working)
    assert_not_equal glyph_at_start, glyph_after
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
