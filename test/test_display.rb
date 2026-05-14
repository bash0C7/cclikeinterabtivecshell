require "test/unit"
require "stringio"
require "cclikesh/display"
require "cclikesh/transcript"

class TestDisplay < Test::Unit::TestCase
  def setup
    Cclikesh::Transcript.clear!
    Cclikesh::Style.init! if defined?(Cclikesh::Style)
    @captured = StringIO.new
    @orig_stdout = $stdout
    $stdout = @captured
    Cclikesh::Display.init
  end

  def teardown
    $stdout = @orig_stdout
    Cclikesh::Display.close
  end

  def test_append_writes_line_and_records_transcript
    Cclikesh::Display.append("hello")
    assert_equal "hello\r\n", @captured.string
    assert_equal ["hello"], Cclikesh::Transcript.lines
  end

  def test_append_with_prompt_concatenates
    Cclikesh::Display.append("world", prompt: "> ")
    assert_equal "> world\r\n", @captured.string
  end

  def test_append_with_style_wraps_sgr
    require "cclikesh/style"
    Cclikesh::Display.append("oops", style: :error)
    assert_equal "\e[31moops\e[0m\r\n", @captured.string
  end

  def test_open_live_then_update_rewrites_last_line
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "step 1")
    Cclikesh::Display.live_update(sid, "step 2")
    expected = "\r\n" + "\e[1A\r\e[K" + "step 1" + "\r\n" + "\e[1A\r\e[K" + "step 2" + "\r\n"
    assert_equal expected, @captured.string
  end

  def test_live_commit_finalizes_with_newline_and_records
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "progress")
    Cclikesh::Display.live_commit(sid, "done")
    assert @captured.string.end_with?("\e[1A\r\e[K" + "done\r\n"), @captured.string.inspect
    assert_equal ["done"], Cclikesh::Transcript.lines
  end

  def test_live_discard_clears_line
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "wip")
    Cclikesh::Display.live_discard(sid)
    assert @captured.string.end_with?("\e[1A\r\e[K\r\n"), @captured.string.inspect
    assert_equal [], Cclikesh::Transcript.lines
  end

  def test_dialog_emits_box
    Cclikesh::Display.dialog("hi")
    lines = @captured.string.split("\n")
    assert_match(/┌─+┐/, lines[0])
    assert_match(/│ hi\s*│/, lines[1])
    assert_match(/└─+┘/, lines[2])
  end
end
