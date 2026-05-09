# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/builder"
require "logger"
require "stringio"

class TestBuilder < Test::Unit::TestCase
  def test_on_submit_stores_block
    b = Cclikesh::Builder.new
    block = proc { |line, ctx| line.upcase }
    b.on_submit(&block)
    assert_same block, b.on_submit_handler
  end

  def test_on_submit_called_twice_replaces
    b = Cclikesh::Builder.new
    b.on_submit { |line, ctx| 1 }
    second = proc { |line, ctx| 2 }
    b.on_submit(&second)
    assert_same second, b.on_submit_handler
  end

  def test_slash_stores_per_name_handler
    b = Cclikesh::Builder.new
    quit_block = proc { |args, ctx| ctx.quit }
    b.slash(:quit, &quit_block)
    assert_same quit_block, b.slash_handler(:quit)
  end

  def test_slash_handler_unknown_returns_nil
    b = Cclikesh::Builder.new
    assert_nil b.slash_handler(:nope)
  end

  def test_slash_accepts_string_name_normalized_to_symbol
    b = Cclikesh::Builder.new
    block = proc { |args, ctx| nil }
    b.slash("quit", &block)
    assert_same block, b.slash_handler(:quit)
  end

  def test_define_style_registers_definition
    b = Cclikesh::Builder.new
    b.define_style(:warn, fg: :yellow, bold: true)
    assert_equal({ fg: :yellow, bold: true }, b.style_definition(:warn))
  end

  def test_style_definition_unknown_returns_nil
    b = Cclikesh::Builder.new
    assert_nil b.style_definition(:unknown)
  end

  def test_define_style_overrides_previous
    b = Cclikesh::Builder.new
    b.define_style(:x, fg: :red)
    b.define_style(:x, fg: :green)
    assert_equal({ fg: :green }, b.style_definition(:x))
  end

  def test_logger_defaults_to_info_level_stderr_progname
    builder = Cclikesh::Builder.new
    logger = builder.logger
    assert_kind_of Logger, logger
    assert_equal Logger::INFO, logger.level
    assert_equal "cclikesh", logger.progname
  end

  def test_log_level_setter_accepts_symbols
    builder = Cclikesh::Builder.new
    builder.log_level = :debug
    assert_equal Logger::DEBUG, builder.logger.level
    builder.log_level = :warn
    assert_equal Logger::WARN, builder.logger.level
  end

  def test_log_to_redirects_output
    io = StringIO.new
    builder = Cclikesh::Builder.new
    builder.log_to(io)
    builder.logger.info("hello")
    assert_match(/hello/, io.string)
  end

  def test_log_to_accepts_file_path_string
    require "tempfile"
    Tempfile.create("cclikesh-log-test") do |f|
      builder = Cclikesh::Builder.new
      builder.log_to(f.path)
      builder.logger.info("path-write")
      f.rewind
      assert_match(/path-write/, File.read(f.path))
    end
  end

  def test_log_to_raises_on_unsupported_target
    builder = Cclikesh::Builder.new
    assert_raise(ArgumentError) { builder.log_to(42) }
  end

  def test_log_level_raises_on_unknown_symbol
    builder = Cclikesh::Builder.new
    assert_raise(ArgumentError) { builder.log_level = :nonsense }
  end

  def test_log_to_preserves_previously_set_log_level
    builder = Cclikesh::Builder.new
    builder.log_level = :debug
    io = StringIO.new
    builder.log_to(io)
    assert_equal Logger::DEBUG, builder.logger.level
    builder.logger.debug("debug-msg")
    assert_match(/debug-msg/, io.string)
  end

  def test_on_state_change_registers_block
    builder = Cclikesh::Builder.new
    called = []
    builder.on_state_change { |k, o, n, _ctx| called << [k, o, n] }
    builder.on_state_change_handler.call(:phase, nil, :working, nil)
    assert_equal [[:phase, nil, :working]], called
  end

  def test_on_start_collects_multiple_handlers_in_registration_order
    builder = Cclikesh::Builder.new
    builder.on_start { |_| 1 }
    builder.on_start { |_| 2 }
    assert_equal 2, builder.on_start_handlers.size
  end

  def test_on_quit_collects_handlers
    builder = Cclikesh::Builder.new
    builder.on_quit { |_| 1 }
    builder.on_quit { |_| 2 }
    assert_equal 2, builder.on_quit_handlers.size
  end

  def test_before_submit_collects_handlers
    builder = Cclikesh::Builder.new
    builder.before_submit { |_, _| 1 }
    builder.before_submit { |_, _| 2 }
    assert_equal 2, builder.before_submit_handlers.size
  end

  def test_after_submit_collects_handlers
    builder = Cclikesh::Builder.new
    builder.after_submit { |_, _| 1 }
    assert_equal 1, builder.after_submit_handlers.size
  end

  def test_on_tab_registers_block
    builder = Cclikesh::Builder.new
    builder.on_tab { |buf, pos, _| [buf, pos] }
    assert_equal ["x", 1], builder.on_tab_handler.call("x", 1, nil)
  end

  def test_before_tab_collects_handlers
    builder = Cclikesh::Builder.new
    builder.before_tab { |_, _, _| 1 }
    builder.before_tab { |_, _, _| 2 }
    assert_equal 2, builder.before_tab_handlers.size
  end

  def test_after_tab_collects_handlers
    builder = Cclikesh::Builder.new
    builder.after_tab { |_, _, _, _| 1 }
    assert_equal 1, builder.after_tab_handlers.size
  end

  def test_tick_interval_default_and_setter
    builder = Cclikesh::Builder.new
    assert_equal 0.06, builder.tick_interval
    builder.tick_interval = 0.1
    assert_equal 0.1, builder.tick_interval
  end

  def test_spinner_block_sets_frames_colors_interval
    builder = Cclikesh::Builder.new
    builder.spinner do |s|
      s.frames = %w[A B C]
      s.colors = [:red, :green]
      s.frame_interval = 0.2
    end
    assert_equal %w[A B C], builder.spinner_frames
    assert_equal [:red, :green], builder.spinner_colors
    assert_equal 0.2, builder.spinner_frame_interval
  end

  def test_spinner_defaults_when_block_not_called
    builder = Cclikesh::Builder.new
    assert_equal %w[✻ ✶ ✷ ✸ ✹], builder.spinner_frames
    assert_equal [:cyan, :magenta], builder.spinner_colors
    assert_equal 0.15, builder.spinner_frame_interval
  end

  def test_spinner_label_registers_block
    builder = Cclikesh::Builder.new
    builder.spinner_label { |_ctx| "Working" }
    assert_equal "Working", builder.spinner_label_proc.call(:ctx)
  end

  def test_idle_phrases_default_loaded_from_file
    builder = Cclikesh::Builder.new
    assert_includes builder.idle_phrases, "Roosting"
    assert_includes builder.idle_phrases, "Mooching"
    assert_equal 20, builder.idle_phrases.size
  end

  def test_idle_phrases_setter_overrides
    builder = Cclikesh::Builder.new
    builder.idle_phrases = %w[Foo Bar]
    assert_equal %w[Foo Bar], builder.idle_phrases
  end

  def test_idle_phrase_interval_default_and_setter
    builder = Cclikesh::Builder.new
    assert_equal 3.0, builder.idle_phrase_interval
    builder.idle_phrase_interval = 5.0
    assert_equal 5.0, builder.idle_phrase_interval
  end

  def test_info_registers_block_with_order
    builder = Cclikesh::Builder.new
    builder.info(:elapsed, order: 10) { |_| "1s" }
    builder.info(:tokens,  order: 20) { |_| "↓ 1k" }
    segs = builder.info_segments
    assert_equal [:elapsed, :tokens], segs.map { |name, _, _| name }
    assert_equal "1s",   segs[0][2].call(:ctx)
    assert_equal "↓ 1k", segs[1][2].call(:ctx)
  end

  def test_info_unspecified_order_uses_registration_order
    builder = Cclikesh::Builder.new
    builder.info(:b) { |_| "b" }
    builder.info(:a, order: 5) { |_| "a" }
    builder.info(:c) { |_| "c" }
    segs = builder.info_segments
    assert_equal :a, segs.first[0]
  end
end
