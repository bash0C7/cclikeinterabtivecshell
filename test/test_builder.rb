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
end
