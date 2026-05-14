require "test/unit"
require "stringio"
require "cclikesh/chrome"

class TestStatusLineRewrite < Test::Unit::TestCase
  def setup
    @captured = StringIO.new
    @orig_stdout = $stdout
    $stdout = @captured
    Cclikesh::Chrome.init
    Cclikesh::Chrome.singleton_class.define_method(:winsize) { [24, 80] }
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_working_phase_emits_full_rewrite_cycle
    Cclikesh::Chrome.update_status_line(phase: :working, info_bar: [{ text: "hi" }])
    s = @captured.string
    assert s.start_with?("\e7"),         "must start with DECSC; got #{s.inspect}"
    assert s.include?("\e[2A"),          "must move up 2 rows; got #{s.inspect}"
    assert s.include?("\r\e[K"),         "must CR + erase line; got #{s.inspect}"
    assert s.include?("hi"),             "must reprint content; got #{s.inspect}"
    assert s.end_with?("\e8"),           "must end with DECRC; got #{s.inspect}"
  end

  def test_idle_after_active_erases_then_restores
    Cclikesh::Chrome.update_status_line(phase: :working, info_bar: [{ text: "x" }])
    @captured.truncate(0)
    @captured.rewind
    Cclikesh::Chrome.update_status_line(phase: :idle, info_bar: [])
    s = @captured.string
    assert s.include?("\e7"),  "idle erase must save cursor; got #{s.inspect}"
    assert s.include?("\e[2A"), "idle erase must move up; got #{s.inspect}"
    assert s.include?("\r\e[K"), "idle erase must erase line; got #{s.inspect}"
    assert s.end_with?("\e8"),  "idle erase must restore cursor; got #{s.inspect}"
    refute Cclikesh::Chrome.working_line_active?
  end

  def test_idle_when_never_active_is_noop
    Cclikesh::Chrome.update_status_line(phase: :idle, info_bar: [])
    assert_equal "", @captured.string
  end

  def test_repeated_working_ticks_each_emit_one_cycle
    Cclikesh::Chrome.update_status_line(phase: :working, info_bar: [{ text: "a" }])
    Cclikesh::Chrome.update_status_line(phase: :working, info_bar: [{ text: "b" }])
    s = @captured.string
    assert_equal 2, s.scan("\e7").length, "expected 2 DECSC saves; got #{s.inspect}"
    assert_equal 2, s.scan("\e8").length, "expected 2 DECRC restores; got #{s.inspect}"
  end
end
