require_relative "test_helper"
require "unicode/display_width"
require "cclikesh/chrome"

class TestJapanesePaint < Test::Unit::TestCase
  def test_truncate_to_width_handles_cjk
    s = "日本語abc"  # widths: 2+2+2+1+1+1 = 9
    truncated = Cclikesh::Chrome.truncate_to_width(s, 5)
    assert Unicode::DisplayWidth.of(truncated) <= 5
    assert truncated.end_with?("…")
  end

  def test_truncate_returns_unchanged_when_under_limit
    assert_equal "短い", Cclikesh::Chrome.truncate_to_width("短い", 10)
  end

  def test_truncate_with_mixed_width_characters
    # Mixed ASCII and CJK
    s = "abc日本"  # widths: 1+1+1+2+2 = 7
    truncated = Cclikesh::Chrome.truncate_to_width(s, 5)
    assert Unicode::DisplayWidth.of(truncated) <= 5
  end

  def test_truncate_with_emoji_like_wide_chars
    # Emoji and other wide characters
    s = "test中文"  # widths: 1+1+1+1+2+2 = 8
    truncated = Cclikesh::Chrome.truncate_to_width(s, 6)
    assert Unicode::DisplayWidth.of(truncated) <= 6
  end

  def test_truncate_single_cjk_char_that_exceeds_limit
    s = "日"  # width: 2
    truncated = Cclikesh::Chrome.truncate_to_width(s, 1)
    # Should just add ellipsis since the char doesn't fit
    assert truncated.end_with?("…")
  end
end
