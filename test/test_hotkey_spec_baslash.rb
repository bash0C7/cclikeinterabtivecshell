# frozen_string_literal: true

require_relative "test_helper"
require "baslash/hotkey_spec"

class TestHotkeySpecBaslash < Test::Unit::TestCase
  def test_parse_ctrl_letter
    assert_equal [7],  Baslash::HotkeySpec.parse("C-g")
    assert_equal [1],  Baslash::HotkeySpec.parse("C-a")
    assert_equal [26], Baslash::HotkeySpec.parse("C-z")
  end

  def test_parse_ctrl_letter_case_insensitive
    assert_equal [7], Baslash::HotkeySpec.parse("c-g")
    assert_equal [7], Baslash::HotkeySpec.parse("C-G")
  end

  def test_parse_meta_letter
    assert_equal [27, 100], Baslash::HotkeySpec.parse("M-d")
    assert_equal [27, 97],  Baslash::HotkeySpec.parse("M-a")
  end

  def test_parse_meta_digit
    assert_equal [27, 49], Baslash::HotkeySpec.parse("M-1")
    assert_equal [27, 48], Baslash::HotkeySpec.parse("M-0")
  end

  def test_parse_chord
    assert_equal [24, 18], Baslash::HotkeySpec.parse("C-x C-r")
  end

  def test_parse_chord_extra_whitespace
    assert_equal [24, 18], Baslash::HotkeySpec.parse("C-x   C-r")
  end

  def test_parse_empty_raises
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("") }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("   ") }
  end

  def test_parse_unknown_token_raises
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("foo") }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("C-") }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("X-y") }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse("M-foo") }
  end

  def test_parse_non_string_raises
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse(nil) }
    assert_raise(Baslash::HotkeyError) { Baslash::HotkeySpec.parse(42) }
  end

  def test_reserved_keys_raise
    %w[C-c C-m C-j C-i C-h].each do |k|
      assert_raise(Baslash::HotkeyError, "expected reserved: #{k}") do
        Baslash::HotkeySpec.parse(k)
      end
    end
  end

  def test_format_canonicalizes
    assert_equal "C-g",     Baslash::HotkeySpec.format("C-g")
    assert_equal "C-g",     Baslash::HotkeySpec.format("c-G")
    assert_equal "M-d",     Baslash::HotkeySpec.format("M-D")
    assert_equal "C-x C-r", Baslash::HotkeySpec.format("c-X c-r")
  end
end
