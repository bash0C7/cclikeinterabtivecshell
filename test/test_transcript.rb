# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/transcript"

class TestTranscript < Test::Unit::TestCase
  def setup
    Cclikesh::Transcript.clear!
  end

  def test_starts_empty
    assert_equal [], Cclikesh::Transcript.lines
  end

  def test_records_appended_line
    Cclikesh::Transcript.record("hello")
    assert_equal ["hello"], Cclikesh::Transcript.lines
  end

  def test_strips_ansi_when_recording
    Cclikesh::Transcript.record("\e[32mok\e[0m")
    assert_equal ["ok"], Cclikesh::Transcript.lines
  end

  def test_lines_returns_a_dup_so_callers_cannot_mutate
    Cclikesh::Transcript.record("a")
    snap = Cclikesh::Transcript.lines
    snap << "external mutation"
    assert_equal ["a"], Cclikesh::Transcript.lines
  end

  def test_clear_resets_to_empty
    Cclikesh::Transcript.record("a")
    Cclikesh::Transcript.record("b")
    Cclikesh::Transcript.clear!
    assert_equal [], Cclikesh::Transcript.lines
  end

  def test_record_skips_nil
    Cclikesh::Transcript.record(nil)
    assert_equal [], Cclikesh::Transcript.lines
  end

  def test_record_skips_empty_string
    Cclikesh::Transcript.record("")
    assert_equal [], Cclikesh::Transcript.lines
  end

  def test_save_writes_lines_to_path
    require "tmpdir"
    Cclikesh::Transcript.record("first")
    Cclikesh::Transcript.record("second")
    path = File.join(Dir.tmpdir, "cclikesh-transcript-test-#{Process.pid}.log")
    Cclikesh::Transcript.save(path)
    body = File.read(path)
    assert_equal "first\nsecond\n", body
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_thread_safe_concurrent_records
    threads = 20.times.map do |i|
      Thread.new { Cclikesh::Transcript.record("line-#{i}") }
    end
    threads.each(&:join)
    assert_equal 20, Cclikesh::Transcript.lines.size
  end
end
