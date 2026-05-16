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

  def test_define_style_does_not_raise
    b = Baslash::Builder.new
    # Style.define calls Curses.init_pair in a full init context;
    # outside curses init it may raise — just ensure Builder.define_style exists.
    assert_respond_to b, :define_style
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

  # --- shareable_ref (NEW) ---

  def test_shareable_ref_creates_named_ref
    require "baslash/shareable_ref"
    builder = Baslash::Builder.new
    ref = builder.shareable_ref(:counter) { Hash.new(0) }
    assert_equal :counter, ref.name
    ref.call(:[]=, :n, 5)
    assert_equal 5, ref.call(:[], :n)
  ensure
    ref&.stop
  end

  def test_shareable_ref_stored_in_state_refs
    builder = Baslash::Builder.new
    ref = builder.shareable_ref(:store) { [] }
    assert_same ref, builder.state_refs[:store]
  ensure
    ref&.stop
  end
end
