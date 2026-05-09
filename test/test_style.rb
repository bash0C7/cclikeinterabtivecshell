# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/style"

class TestStyle < Test::Unit::TestCase
  def test_wrap_default_returns_text_unchanged
    assert_equal "hi", Cclikesh::Style.wrap("hi", :default)
  end

  def test_wrap_nil_style_returns_text_unchanged
    assert_equal "hi", Cclikesh::Style.wrap("hi", nil)
  end

  def test_wrap_result_uses_green
    assert_equal "\e[32mhi\e[0m", Cclikesh::Style.wrap("hi", :result)
  end

  def test_wrap_error_uses_red
    assert_equal "\e[31mboom\e[0m", Cclikesh::Style.wrap("boom", :error)
  end

  def test_wrap_prompt_uses_cyan
    assert_equal "\e[36m> \e[0m", Cclikesh::Style.wrap("> ", :prompt)
  end

  def test_wrap_thinking_uses_magenta
    assert_equal "\e[35m...\e[0m", Cclikesh::Style.wrap("...", :thinking)
  end

  def test_wrap_dim_uses_dim
    assert_equal "\e[2mdim\e[0m", Cclikesh::Style.wrap("dim", :dim)
  end

  def test_wrap_custom_with_fg_only
    custom = { fg: :yellow }
    assert_equal "\e[33mhi\e[0m", Cclikesh::Style.wrap("hi", :my, custom: custom)
  end

  def test_wrap_custom_with_fg_and_bold
    custom = { fg: :cyan, bold: true }
    assert_equal "\e[1;36mhi\e[0m", Cclikesh::Style.wrap("hi", :my, custom: custom)
  end

  def test_wrap_unknown_style_with_no_custom_returns_text
    assert_equal "hi", Cclikesh::Style.wrap("hi", :unknown_xyz)
  end
end
