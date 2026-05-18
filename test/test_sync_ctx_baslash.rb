# frozen_string_literal: true

require "test/unit"
require "stringio"
require "logger"
require "baslash/sync_ctx"
require "baslash/display"
require "baslash/context"
require "baslash/title_bar"

class TestSyncCtxBaslash < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::Display.reset_for_test
    Baslash::Context.init(logger: Logger.new(IO::NULL))
    @ctx = Baslash::SyncCtx.new(logger: Baslash::Context.logger)
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_display_append_writes_to_stdout
    @ctx.display.append("hello")
    assert_includes $stdout.string, "hello"
  end

  def test_display_append_with_style
    @ctx.display.append("hi", style: :bold)
    assert_includes $stdout.string, "\e[1mhi\e[0m"
  end

  def test_display_open_live_returns_slot
    slot = @ctx.display.open_live
    assert_respond_to slot, :update
    assert_respond_to slot, :commit
    assert_respond_to slot, :discard
  end

  def test_display_dialog_emits_box
    @ctx.display.dialog("hi")
    assert_match(/┌─+┐/, $stdout.string)
  end

  def test_state_is_writable
    @ctx.state[:phase] = :working
    assert_equal :working, @ctx.state[:phase]
    assert_equal :working, Baslash::Context.state[:phase]
  end

  def test_logger_is_accessible
    assert_respond_to @ctx.logger, :info
  end

  def test_quit_marks_context_quit
    @ctx.quit
    assert Baslash::Context.quit?
  end

  def test_display_raw_emit_writes_bytes_to_stdout
    @ctx.display.raw_emit("\e]0;hello\a")
    assert_includes $stdout.string, "\e]0;hello\a"
  end

end
