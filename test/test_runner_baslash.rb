# frozen_string_literal: true

require "test/unit"
require "baslash/runner"
require "baslash/builder"

class TestRunnerBaslash < Test::Unit::TestCase
  def test_prompt_text_returns_cyan_default
    builder = Baslash::Builder.new
    assert_equal "\e[36m> \e[0m", Baslash::Runner.prompt_text(builder)
  end

  def test_install_completion_no_op_without_handler
    builder = Baslash::Builder.new
    assert_nothing_raised { Baslash::Runner.install_completion(builder) }
  end

  def test_install_completion_installs_default_proc_for_slash_completion
    builder = Baslash::Builder.new
    builder.slash(:hello, description: "say hi") { |_, _| }
    Baslash::Runner.install_completion(builder)
    result = Reline.completion_proc.call("/hel")
    assert_includes result, "/hello"
  end

  def test_install_completion_respects_user_on_tab_handler
    builder = Baslash::Builder.new
    custom = ->(_) { ["from_user"] }
    builder.on_tab(&custom)
    Baslash::Runner.install_completion(builder)
    assert_same custom, Reline.completion_proc
  end

  def test_run_module_methods_exist
    %i[run prompt_text install_completion].each do |sym|
      assert_respond_to Baslash::Runner, sym, "Runner should respond to #{sym}"
    end
  end
end
