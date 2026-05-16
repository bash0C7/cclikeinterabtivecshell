# frozen_string_literal: true

require_relative "test_helper"
require "baslash/transcript"

class TestTranscriptBaslash < Test::Unit::TestCase
  def setup
    # Exercise the new reset_for_test alias added in Task 5.
    Baslash::Transcript.reset_for_test
  end

  def test_starts_empty
    assert_equal [], Baslash::Transcript.lines
  end

  def test_records_appended_line
    Baslash::Transcript.record("hello")
    assert_equal ["hello"], Baslash::Transcript.lines
  end

  def test_strips_ansi_when_recording
    Baslash::Transcript.record("\e[32mok\e[0m")
    assert_equal ["ok"], Baslash::Transcript.lines
  end

  def test_lines_returns_a_dup_so_callers_cannot_mutate
    Baslash::Transcript.record("a")
    snap = Baslash::Transcript.lines
    snap << "external mutation"
    assert_equal ["a"], Baslash::Transcript.lines
  end

  def test_clear_resets_to_empty
    Baslash::Transcript.record("a")
    Baslash::Transcript.record("b")
    Baslash::Transcript.clear!
    assert_equal [], Baslash::Transcript.lines
  end

  def test_record_skips_nil
    Baslash::Transcript.record(nil)
    assert_equal [], Baslash::Transcript.lines
  end

  def test_record_skips_empty_string
    Baslash::Transcript.record("")
    assert_equal [], Baslash::Transcript.lines
  end

  def test_save_writes_lines_to_path
    require "tmpdir"
    Baslash::Transcript.record("first")
    Baslash::Transcript.record("second")
    path = File.join(Dir.tmpdir, "baslash-transcript-test-#{Process.pid}.log")
    Baslash::Transcript.save(path)
    body = File.read(path)
    assert_equal "first\nsecond\n", body
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_thread_safe_concurrent_records
    threads = 20.times.map do |i|
      Thread.new { Baslash::Transcript.record("line-#{i}") }
    end
    threads.each(&:join)
    assert_equal 20, Baslash::Transcript.lines.size
  end
end
