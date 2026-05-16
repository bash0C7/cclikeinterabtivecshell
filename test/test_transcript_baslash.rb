require "test/unit"
require "baslash/transcript"

class TestTranscriptBaslash < Test::Unit::TestCase
  def setup
    Baslash::Transcript.reset_for_test if Baslash::Transcript.respond_to?(:reset_for_test)
  end

  def test_record_appends_line
    Baslash::Transcript.record("hello")
    assert Baslash::Transcript.lines.include?("hello")
  end

  def test_lines_returns_array
    assert_kind_of Array, Baslash::Transcript.lines
  end
end
