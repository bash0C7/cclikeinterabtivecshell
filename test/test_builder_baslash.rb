# frozen_string_literal: true

require_relative "test_helper"
require "baslash/builder"
require "logger"
require "stringio"

class TestBuilderBaslash < Test::Unit::TestCase
  # --- on_submit ---

  def test_on_submit_stores_shareable_proc
    b = Baslash::Builder.new
    b.on_submit { |args, ctx| args.first.upcase }
    assert_not_nil b.on_submit_handler
  end

  def test_on_submit_called_twice_replaces
    b = Baslash::Builder.new
    b.on_submit { |args, ctx| 1 }
    b.on_submit { |args, ctx| 2 }
    # handler replaced; callable with args convention
    assert_equal 2, b.on_submit_handler.call(["x"], nil)
  end

  # --- slash + slash_registry ---

  def test_slash_registers_into_slash_registry
    b = Baslash::Builder.new
    b.slash(:foo, description: "foo cmd") { |args, ctx| }
    entry = b.slash_registry.lookup(:foo)
    refute_nil entry
    assert_equal "foo cmd", entry[:description]
  end

  def test_slash_handler_unknown_returns_nil
    b = Baslash::Builder.new
    assert_nil b.slash_registry.lookup(:nope)
  end

  def test_slash_accepts_string_name_normalized_to_symbol
    b = Baslash::Builder.new
    b.slash("quit") { |args, ctx| nil }
    refute_nil b.slash_registry.lookup(:quit)
  end

  # --- define_style ---

  def test_define_style_is_a_no_op_stub
    b = Baslash::Builder.new
    # Baslash::Style is SGR-based with fixed named styles; define_style is a
    # backward-compat no-op for examples until Task 11 migrates them.
    assert_respond_to b, :define_style
    assert_nil b.define_style(:warn, fg: :yellow, bold: true)
  end

  # --- logger ---

  def test_logger_defaults_to_info_level_stderr_progname
    builder = Baslash::Builder.new
    logger = builder.logger
    assert_kind_of Logger, logger
    assert_equal Logger::INFO, logger.level
    assert_equal "baslash", logger.progname
  end

  # --- on_start / on_quit ---

  def test_on_start_collects_multiple_handlers_in_registration_order
    builder = Baslash::Builder.new
    builder.on_start { |_| 1 }
    builder.on_start { |_| 2 }
    assert_equal 2, builder.on_start_handlers.size
  end

  def test_on_quit_collects_handlers
    builder = Baslash::Builder.new
    builder.on_quit { |_| 1 }
    builder.on_quit { |_| 2 }
    assert_equal 2, builder.on_quit_handlers.size
  end

  # --- on_tab ---

  def test_on_tab_registers_block
    builder = Baslash::Builder.new
    builder.on_tab { |buf, pos, _| [buf, pos] }
    assert_equal ["x", 1], builder.on_tab_handler.call("x", 1, nil)
  end

  # --- spinner_label ---

  def test_spinner_label_registers_block
    builder = Baslash::Builder.new
    builder.spinner_label { |_ctx| "Working" }
    assert_equal "Working", builder.spinner_label_block.call(:ctx)
  end

  # --- info ---

  def test_info_registers_block_with_order
    builder = Baslash::Builder.new
    builder.info(:elapsed, order: 10) { |_| "1s" }
    builder.info(:tokens,  order: 20) { |_| "↓ 1k" }
    segs = builder.info_blocks.sort_by { |b| b[:order] }
    assert_equal [:elapsed, :tokens], segs.map { |b| b[:name] }
    assert_equal "1s",   segs[0][:block].call(:ctx)
    assert_equal "↓ 1k", segs[1][:block].call(:ctx)
  end

  def test_info_unspecified_order_uses_registration_order
    builder = Baslash::Builder.new
    builder.info(:b) { |_| "b" }
    builder.info(:a, order: 5) { |_| "a" }
    builder.info(:c) { |_| "c" }
    segs = builder.info_blocks.sort_by { |b| b[:order] }
    assert_equal :a, segs.first[:name]
  end

  # --- prompt_suggestion ---

  def test_prompt_suggestion_registers_block
    builder = Baslash::Builder.new
    builder.prompt_suggestion { |_| "try /help" }
    assert_equal "try /help", builder.prompt_suggestion_block.call(nil)
  end

  # --- shortcuts_hint ---

  def test_shortcuts_hint_stores_text
    builder = Baslash::Builder.new
    builder.shortcuts_hint "? for help"
    assert_equal "? for help", builder.shortcuts_hint_text
  end

  # --- header ---

  def test_header_stores_config
    builder = Baslash::Builder.new
    builder.header do |h|
      h.logo "✻"
      h.title "MyShell"
      h.version "v1.0"
    end
    cfg = builder.header_config
    assert_equal "✻", cfg[:logo]
    assert_equal "MyShell", cfg[:title]
    assert_equal "v1.0", cfg[:version]
  end

  def test_header_lines_applies_color_styling
    builder = Baslash::Builder.new
    builder.header do |h|
      h.logo "✻"
      h.title "MyShell"
      h.version "v1.0"
      h.subtitle "a small shell"
      h.note "help is here"
    end
    lines = builder.header_lines
    # First line should contain cyan logo + bold title + dim version
    assert_includes lines[0], "\e[36m"  # cyan
    assert_includes lines[0], "\e[1m"   # bold
    assert_includes lines[0], "\e[2m"   # dim
    # Strip styling and verify content is preserved
    stripped = Baslash::Style.strip(lines[0])
    assert_includes stripped, "✻"
    assert_includes stripped, "MyShell"
    assert_includes stripped, "v1.0"
    # subtitle and note should be present as dim
    assert_includes lines[1], "\e[2m"
    assert_includes Baslash::Style.strip(lines[1]), "a small shell"
    assert_includes lines[2], "\e[2m"
    assert_includes Baslash::Style.strip(lines[2]), "help is here"
  end

  def test_header_lines_omits_empty_fields
    builder = Baslash::Builder.new
    builder.header do |h|
      h.title "OnlyTitle"
    end
    lines = builder.header_lines
    assert_equal 1, lines.size
    assert_includes Baslash::Style.strip(lines[0]), "OnlyTitle"
  end

  # --- prompt_prefix ---

  def test_prompt_prefix_dsl_stores_block
    b = Baslash::Builder.new
    b.prompt_prefix { |_ctx| "cwd-stub" }
    refute_nil b.instance_variable_get(:@prompt_prefix_block)
  end

  def test_prompt_prefix_returns_self_for_chaining
    b = Baslash::Builder.new
    result = b.prompt_prefix { |_ctx| "x" }
    assert_same b, result
  end

  def test_evaluate_prompt_prefix_returns_block_value
    require "baslash/main_ctx"
    b = Baslash::Builder.new
    b.prompt_prefix { |_ctx| "static-result" }
    main_ctx = Baslash::MainCtx.new
    assert_equal "static-result", b.evaluate_prompt_prefix(main_ctx)
  end

  def test_evaluate_prompt_prefix_returns_nil_without_block
    require "baslash/main_ctx"
    b = Baslash::Builder.new
    main_ctx = Baslash::MainCtx.new
    assert_nil b.evaluate_prompt_prefix(main_ctx)
  end

  def test_evaluate_prompt_prefix_rescues_block_exceptions_and_logs
    require "baslash/main_ctx"
    require "stringio"
    io = StringIO.new
    b = Baslash::Builder.new
    # swap in a capturing logger before the rescue path so we can verify
    # the error is reported (no silent rescue).
    captured_logger = Logger.new(io)
    Baslash::Context.init(logger: captured_logger)
    b.prompt_prefix { |_| raise "boom" }
    main_ctx = Baslash::MainCtx.new
    assert_nil b.evaluate_prompt_prefix(main_ctx)
    assert_includes io.string, "prompt_prefix block raised"
    assert_includes io.string, "boom"
  end

  # --- state initializer (new) ---

  def test_state_registers_initializer_block
    b = Baslash::Builder.new
    b.state(:counter) { 42 }
    assert_kind_of Proc, b.state_initializers[:counter]
    assert_equal 42, b.state_initializers[:counter].call
  end

  def test_state_normalizes_string_name_to_symbol
    b = Baslash::Builder.new
    b.state("counter") { 0 }
    assert b.state_initializers.key?(:counter)
  end

  def test_state_returns_self_for_chaining
    b = Baslash::Builder.new
    result = b.state(:x) { 1 }
    assert_same b, result
  end
end
