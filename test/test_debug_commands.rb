# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/debug_commands"

class TestDebugCommandsEscapeInterpreter < Test::Unit::TestCase
  P = Cclikesh::DebugCommands::EscapeInterpreter

  def test_plain_text_passes_through
    assert_equal "hello world", P.parse("hello world")
  end

  def test_e_escape
    assert_equal "\e", P.parse("\\e")
  end

  def test_e_in_csi_sequence
    assert_equal "\e[3m", P.parse("\\e[3m")
  end

  def test_n_r_t_backslash_escapes
    assert_equal "\n", P.parse("\\n")
    assert_equal "\r", P.parse("\\r")
    assert_equal "\t", P.parse("\\t")
    assert_equal "\\", P.parse("\\\\")
  end

  def test_hex_escape
    assert_equal "\xc2\xa0".b, P.parse("\\xc2\\xa0").b
  end

  def test_unknown_escape_raises
    assert_raise(ArgumentError) { P.parse("\\z") }
  end

  def test_incomplete_hex_escape_raises
    assert_raise(ArgumentError) { P.parse("\\x1") }
    assert_raise(ArgumentError) { P.parse("\\x") }
  end

  def test_non_hex_in_hex_escape_raises
    assert_raise(ArgumentError) { P.parse("\\xgg") }
  end

  def test_trailing_backslash_raises
    assert_raise(ArgumentError) { P.parse("foo\\") }
  end
end
