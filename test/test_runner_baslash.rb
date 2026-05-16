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

  def test_drain_residual_stdin_skips_when_stdin_not_tty
    # $stdin under `rake test` is not a TTY, so drain must be a no-op.
    # This verifies the .tty? guard short-circuits before touching IO.
    assert_false $stdin.tty?, "precondition: test runner stdin should not be a TTY"
    assert_nothing_raised { Baslash::Runner.drain_residual_stdin }
  end

  def test_drain_residual_stdin_is_idempotent
    # Multiple back-to-back invocations should be safe.
    assert_nothing_raised do
      3.times { Baslash::Runner.drain_residual_stdin }
    end
  end
end
