# frozen_string_literal: true

require "test/unit"
require "baslash/runner"
require "baslash/builder"

class TestRunnerBaslash < Test::Unit::TestCase
  def test_prompt_text_returns_default
    builder = Baslash::Builder.new
    assert_equal "> ", Baslash::Runner.prompt_text(builder)
  end

  def test_install_completion_no_op_without_handler
    builder = Baslash::Builder.new
    assert_nothing_raised { Baslash::Runner.install_completion(builder) }
  end

  def test_run_module_methods_exist
    %i[run prompt_text install_completion].each do |sym|
      assert_respond_to Baslash::Runner, sym, "Runner should respond to #{sym}"
    end
  end
end
