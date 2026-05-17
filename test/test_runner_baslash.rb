# frozen_string_literal: true

require "test/unit"
require "baslash/runner"
require "baslash/builder"
require "baslash/main_ctx"
require "logger"

class TestRunnerBaslash < Test::Unit::TestCase
  def test_prompt_text_returns_bold_cyan_default
    builder = Baslash::Builder.new
    assert_equal "\e[1;36m> \e[0m", Baslash::Runner.prompt_text(builder)
  end

  def test_compose_prompt_without_prefix_returns_bold_cyan_default
    builder = Baslash::Builder.new
    Baslash::Context.init(logger: Logger.new(IO::NULL))
    main_ctx = Baslash::MainCtx.new
    assert_equal "\e[1;36m> \e[0m", Baslash::Runner.compose_prompt(builder, main_ctx)
  end

  def test_compose_prompt_with_prefix_block_embeds_prefix_text
    builder = Baslash::Builder.new
    builder.prompt_prefix { |_ctx| "/some/path" }
    Baslash::Context.init(logger: Logger.new(IO::NULL))
    main_ctx = Baslash::MainCtx.new
    result = Baslash::Runner.compose_prompt(builder, main_ctx)
    assert_includes result, "/some/path"
    assert_includes result, "> "
    # leading bold-cyan SGR
    assert(result.start_with?("\e[1;36m"))
  end

  def test_compose_prompt_with_empty_prefix_falls_back_to_default
    builder = Baslash::Builder.new
    builder.prompt_prefix { |_ctx| "" }
    Baslash::Context.init(logger: Logger.new(IO::NULL))
    main_ctx = Baslash::MainCtx.new
    assert_equal "\e[1;36m> \e[0m", Baslash::Runner.compose_prompt(builder, main_ctx)
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

  def test_compose_prompt_used_in_prompt_proc_returns_first_line_only_for_multiline
    builder = Baslash::Builder.new
    builder.prompt_prefix { |_ctx| "/cwd" }
    Baslash::Context.init(logger: Logger.new(IO::NULL))

    # Simulate the prompt_proc behavior manually (mirrors what
    # Runner.run installs onto Reline.prompt_proc before the main loop).
    main_ctx = Baslash::MainCtx.new
    proc_fn = ->(lines) {
      first = Baslash::Runner.compose_prompt(builder, main_ctx)
      lines.each_with_index.map { |_, i| i.zero? ? first : "" }
    }

    result = proc_fn.call(["aa", "a", ""])
    assert_equal 3, result.size
    assert_includes result[0], "/cwd"
    assert_equal "", result[1]
    assert_equal "", result[2]
  end

  def test_state_initializers_run_at_boot_populating_context_state
    # Verify Runner calls each state initializer once at boot and stores
    # the result in Baslash::Context.state under the same symbol key.
    builder = Baslash::Builder.new
    builder.state(:counter) { { hits: 0 } }
    builder.state(:greeting) { "hello" }

    Baslash::Context.init(logger: Logger.new(IO::NULL))
    Baslash::Runner.send(:run_state_initializers, builder)

    assert_equal({ hits: 0 }, Baslash::Context.state[:counter])
    assert_equal "hello",     Baslash::Context.state[:greeting]
  end
end
