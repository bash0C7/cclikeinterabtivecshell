# frozen_string_literal: true

require_relative "test_helper"
require "curses"
require "cclikesh/style"
require "cclikesh/chrome"
require "cclikesh/display"
require "cclikesh/transcript"

class TestDisplay < Test::Unit::TestCase
  def setup
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
    Cclikesh::Chrome.init
    Cclikesh::Display.init
    Cclikesh::Transcript.clear!
  end

  def teardown
    Cclikesh::Display.close
    Cclikesh::Chrome.close
    Curses.close_screen
    Cclikesh::Transcript.clear!
  rescue
    nil
  end

  def test_append_writes_to_pad_and_records_transcript
    Cclikesh::Display.append("hello world")
    assert_equal ["hello world"], Cclikesh::Transcript.lines
  end

  def test_append_with_prompt_concatenates
    Cclikesh::Display.append("ok", prompt: "> ")
    assert_equal ["> ok"], Cclikesh::Transcript.lines
  end

  def test_open_live_returns_sid_and_increments
    s1 = Cclikesh::Display.open_live(style: :thinking)
    s2 = Cclikesh::Display.open_live
    assert s1.is_a?(Integer)
    assert_not_equal s1, s2
  end

  def test_live_update_overwrites_slot_text
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "step 1")
    Cclikesh::Display.live_update(sid, "step 2")
    state = Cclikesh::Display.live_slot_state[sid]
    assert_equal "step 2", state[:last_text]
  end

  def test_live_commit_writes_to_transcript_and_removes_slot
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "tmp")
    Cclikesh::Display.live_commit(sid, "DONE")
    assert_includes Cclikesh::Transcript.lines, "DONE"
    assert_nil Cclikesh::Display.live_slot_state[sid]
  end

  def test_live_discard_removes_slot_without_transcript
    sid = Cclikesh::Display.open_live
    Cclikesh::Display.live_update(sid, "abc")
    Cclikesh::Display.live_discard(sid)
    refute_includes Cclikesh::Transcript.lines, "abc"
    assert_nil Cclikesh::Display.live_slot_state[sid]
  end

  def test_dialog_appends_box_lines_to_transcript
    Cclikesh::Display.dialog("hello\nworld")
    lines = Cclikesh::Transcript.lines
    assert lines.first.start_with?("┌"), "first line should start with ┌, got #{lines.first.inspect}"
    assert(lines.any? { |l| l.include?("hello") })
    assert(lines.any? { |l| l.include?("world") })
    assert lines.last.start_with?("└"), "last line should start with └, got #{lines.last.inspect}"
  end
end
