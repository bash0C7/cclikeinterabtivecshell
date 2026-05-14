require "test/unit"
require "stringio"
require "unicode/display_width"
require "cclikesh/chrome"

class TestChrome < Test::Unit::TestCase
  def setup
    @captured = StringIO.new
    @orig_stdout = $stdout
    $stdout = @captured
    Cclikesh::Chrome.init
  end

  def teardown
    $stdout = @orig_stdout
    Cclikesh::Chrome.close
  end

  def stub_winsize(cols, rows)
    Cclikesh::Chrome.singleton_class.define_method(:winsize) { [rows, cols] }
  end

  def test_init_starts_with_no_working_line
    refute Cclikesh::Chrome.working_line_active?
  end

  def test_print_turn_chrome_emits_dividers_and_footer
    stub_winsize(25, 24)
    Cclikesh::Chrome.print_turn_chrome(
      status_rows:    [{ segments: [{ text: "ready" }] }],
      shortcuts_hint: "Type / for cmds"
    )
    s = @captured.string
    assert_match(/─{25}/, s)
    assert_match(/ready · Type \/ for cmds/, s)
  end

  def test_print_turn_chrome_truncates_to_winsize
    stub_winsize(10, 24)
    Cclikesh::Chrome.print_turn_chrome(
      status_rows:    [],
      shortcuts_hint: "very long shortcuts hint that should be cut"
    )
    s = @captured.string
    last_line = s.lines.reject(&:empty?).last
    plain = last_line.gsub(/\e\[[0-9;]*m/, "").chomp
    dw = Unicode::DisplayWidth.of(plain)
    assert dw <= 10, "display-width #{dw} exceeds 10: got #{plain.inspect}"
  end

  def test_update_status_line_writes_ansi_rewrite_when_working
    stub_winsize(40, 24)
    Cclikesh::Chrome.update_status_line(phase: :working, info_bar: [{ text: "loading" }])
    s = @captured.string
    assert s.include?("\e7"),    s.inspect
    assert s.include?("\e[2A"),  s.inspect
    assert s.include?("\r\e[K"), s.inspect
    assert s.include?("loading"), s.inspect
    assert s.end_with?("\e8"),   s.inspect
    assert Cclikesh::Chrome.working_line_active?
  end

  def test_update_status_line_erases_when_idle_after_active
    stub_winsize(40, 24)
    Cclikesh::Chrome.update_status_line(phase: :working, info_bar: [{ text: "x" }])
    Cclikesh::Chrome.update_status_line(phase: :idle,    info_bar: [])
    refute Cclikesh::Chrome.working_line_active?
  end

  def test_handle_resize_marks_dirty_and_clears_on_next_winsize_call
    Cclikesh::Chrome.handle_resize
    assert Cclikesh::Chrome.winsize_dirty?
    Cclikesh::Chrome.consume_winsize_dirty
    refute Cclikesh::Chrome.winsize_dirty?
  end
end
