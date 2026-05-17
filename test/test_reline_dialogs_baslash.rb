# frozen_string_literal: true

require "test/unit"
require "stringio"
require "logger"
require "baslash/title_bar"
require "baslash/builder"
require "baslash/main_ctx"
require "baslash/context"
require "baslash/reline_dialogs"

class TestRelineDialogsBaslash < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::TitleBar.reset_for_test
    Baslash::Context.reset!
    Baslash::Context.init(logger: Logger.new(StringIO.new))
    @builder = Baslash::Builder.new
    # Builder DSL: info(name, &block) registers an info_bar entry; block returns text.
    @builder.info(:ctx_label) { |_ctx| "ctx" }
    @main_ctx = Baslash::MainCtx.new(@builder.state_refs)
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_run_tick_drives_title_bar
    Baslash::RelineDialogs.run_tick(@builder, @main_ctx)
    assert_match(/\A\e\]0;✻ /, $stdout.string)
    assert_includes $stdout.string, "ctx"
  end

  def test_run_tick_increments_title_bar_count
    initial = Baslash::TitleBar.tick_count
    Baslash::RelineDialogs.run_tick(@builder, @main_ctx)
    assert_equal initial + 1, Baslash::TitleBar.tick_count
  end

  def test_compose_ctx_text_joins_with_dot
    text = Baslash::RelineDialogs.compose_ctx_text(@builder, @main_ctx)
    assert_equal "ctx", text
  end

  def test_format_slash_line_uses_bright_black_no_dim
    item = { name: "hello", description: "say hi" }
    line = Baslash::RelineDialogs.format_slash_line(item)
    assert_includes line, "\e[90m"
    refute_includes line, "\e[2;90m"
  end

  def test_format_ghost_hint_uses_bright_black_no_dim
    formatted = Baslash::RelineDialogs.format_ghost_hint("try this")
    assert_includes formatted, "\e[90m"
    refute_includes formatted, "\e[2;90m"
  end
end
