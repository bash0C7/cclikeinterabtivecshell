require "test/unit"
require "stringio"
require "baslash/display"

class TestDisplay < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::Display.reset_for_test
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_append_writes_line_with_newline
    Baslash::Display.append("hello")
    assert_equal "hello\n", $stdout.string
  end

  def test_append_with_style_wraps_in_sgr
    Baslash::Display.append("hi", style: :bold)
    assert_equal "\e[1mhi\e[0m\n", $stdout.string
  end

  def test_append_records_transcript
    require "baslash/transcript"
    Baslash::Transcript.reset_for_test if Baslash::Transcript.respond_to?(:reset_for_test)
    Baslash::Display.append("hi")
    assert Baslash::Transcript.lines.include?("hi"), "transcript should capture appended line"
  end if defined?(Baslash::Transcript)

  def test_open_live_returns_unique_sid
    sid1 = Baslash::Display.open_live
    sid2 = Baslash::Display.open_live
    refute_equal sid1, sid2
  end

  def test_live_update_emits_cr_clear_text
    sid = Baslash::Display.open_live
    $stdout.truncate(0); $stdout.rewind
    Baslash::Display.live_update(sid, "first")
    assert_equal "\r\e[K\e[1G\e[0mfirst\e[0m", $stdout.string
  end

  def test_live_commit_finalizes_with_newline
    sid = Baslash::Display.open_live
    Baslash::Display.live_update(sid, "intermediate")
    $stdout.truncate(0); $stdout.rewind
    Baslash::Display.live_commit(sid, "final value")
    assert_equal "\r\e[K\e[1G\e[0mfinal value\e[0m\n", $stdout.string
  end

  def test_live_discard_emits_cr_clear_no_newline
    sid = Baslash::Display.open_live
    Baslash::Display.live_update(sid, "anything")
    $stdout.truncate(0); $stdout.rewind
    Baslash::Display.live_discard(sid)
    assert_equal "\r\e[K", $stdout.string
  end

  def test_dialog_renders_box
    Baslash::Display.dialog("hello\nworld")
    out = $stdout.string
    assert_match(/┌─+┐/, out)
    assert_match(/│ hello/, out)
    assert_match(/│ world/, out)
    assert_match(/└─+┘/, out)
  end

  def test_raw_emit_writes_bytes_verbatim
    Baslash::Display.raw_emit("ABC\e[31mred\e[0m")
    assert_includes $stdout.string, "ABC\e[31mred\e[0m"
  end
end
