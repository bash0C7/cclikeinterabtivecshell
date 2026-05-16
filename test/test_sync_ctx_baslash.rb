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
    @ctx = Baslash::SyncCtx.new(state_refs: {}, logger: Baslash::Context.logger)
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

  def test_shareable_returns_proxy_for_registered_ref
    ref = MiniRef.new
    ctx = Baslash::SyncCtx.new(state_refs: { mini: ref }, logger: Baslash::Context.logger)
    proxy = ctx.shareable(:mini)
    assert_equal :ok, proxy.call(:ping)
  end

  def test_shareable_raises_for_unknown_name
    assert_raise(ArgumentError) { @ctx.shareable(:nope) }
  end

  def test_display_raw_emit_writes_to_stdout
    @ctx.display.raw_emit("hello\e[31mred\e[0m")
    assert_equal "hello\e[31mred\e[0m", $stdout.string
  end

  def test_debug_snapshot_returns_state_and_phase
    Baslash::Context.state[:x] = 42
    Baslash::TitleBar.tick(phase: :working, ctx_text: "test")
    snap = @ctx.debug_snapshot
    assert_kind_of String, snap[:context_state]
    assert_kind_of String, snap[:title_bar_phase]
    assert_includes snap[:title_bar_phase], "working"
  end

  def test_debug_tick_count_returns_title_bar_count
    Baslash::TitleBar.reset_for_test
    Baslash::TitleBar.tick(phase: :ready, ctx_text: "a")
    Baslash::TitleBar.tick(phase: :ready, ctx_text: "b")
    assert_equal 2, @ctx.debug_tick_count
  end

  def test_debug_curses_caps_returns_term
    original = ENV["TERM"]
    ENV["TERM"] = "xterm-256color"
    caps = @ctx.debug_curses_caps
    assert_equal "xterm-256color", caps[:term]
  ensure
    ENV["TERM"] = original
  end

  class MiniRef
    def call(method, *)
      :ok if method == :ping
    end
    def stop; end
  end
end
