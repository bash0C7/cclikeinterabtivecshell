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
end
