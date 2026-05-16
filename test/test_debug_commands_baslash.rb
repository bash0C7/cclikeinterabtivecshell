# frozen_string_literal: true

require_relative "test_helper"
require "baslash/debug_commands"
require "baslash/slash_registry"
require "baslash/builder"

class TestDebugCommandsEscapeInterpreterBaslash < Test::Unit::TestCase
  P = Baslash::DebugCommands::EscapeInterpreter

  def test_plain_text_passes_through
    assert_equal "hello world", P.parse("hello world")
  end

  def test_e_escape
    assert_equal "\e", P.parse("\\e")
  end

  def test_e_in_csi_sequence
    assert_equal "\e[3m", P.parse("\\e[3m")
  end

  def test_n_r_t_backslash_escapes
    assert_equal "\n", P.parse("\\n")
    assert_equal "\r", P.parse("\\r")
    assert_equal "\t", P.parse("\\t")
    assert_equal "\\", P.parse("\\\\")
  end

  def test_hex_escape
    assert_equal "\xc2\xa0".b, P.parse("\\xc2\\xa0").b
  end

  def test_unknown_escape_raises
    assert_raise(ArgumentError) { P.parse("\\z") }
  end

  def test_incomplete_hex_escape_raises
    assert_raise(ArgumentError) { P.parse("\\x1") }
    assert_raise(ArgumentError) { P.parse("\\x") }
  end

  def test_non_hex_in_hex_escape_raises
    assert_raise(ArgumentError) { P.parse("\\xgg") }
  end

  def test_trailing_backslash_raises
    assert_raise(ArgumentError) { P.parse("foo\\") }
  end
end

class TestDebugCommandsRegisterBaslash < Test::Unit::TestCase
  def setup
    @registry = Baslash::SlashRegistry.new
    @runtime_state = { tick_counter: nil }
    Baslash::DebugCommands.register(@registry, @runtime_state)
  end

  def test_seven_commands_registered
    %i[debug-sleep debug-emit debug-color-probe debug-tick-counter
       debug-curses-caps debug-snapshot debug-frame-dump].each do |name|
      refute_nil @registry.lookup(name), "expected /#{name} to be registered"
    end
  end

  def test_debug_sleep_rejects_non_numeric
    ctx = StubCtx.new
    @registry.lookup(:"debug-sleep")[:body].call(["abc"], ctx)
    assert(ctx.appended_texts.any? { |t| t.include?("usage:") }, ctx.appended_texts.inspect)
    refute ctx.quit_called?
  end

  def test_debug_sleep_rejects_negative
    ctx = StubCtx.new
    @registry.lookup(:"debug-sleep")[:body].call(["-1"], ctx)
    assert(ctx.appended_texts.any? { |t| t.include?("usage:") })
  end

  def test_debug_sleep_rejects_too_large
    ctx = StubCtx.new
    @registry.lookup(:"debug-sleep")[:body].call(["61"], ctx)
    assert(ctx.appended_texts.any? { |t| t.include?("usage:") })
  end

  def test_debug_emit_rejects_empty
    ctx = StubCtx.new
    @registry.lookup(:"debug-emit")[:body].call([], ctx)
    assert(ctx.appended_texts.any? { |t| t.include?("usage:") })
  end

  def test_debug_emit_rejects_bad_escape
    ctx = StubCtx.new
    @registry.lookup(:"debug-emit")[:body].call(["\\z"], ctx)
    assert(ctx.appended_texts.any? { |t| t.include?("usage:") || t.include?("unknown escape") }, ctx.appended_texts.inspect)
  end

  class StubCtx
    def initialize
      @quit = false
      @appended = []
      @state = {}
    end

    attr_reader :state

    def quit;            @quit = true;       end
    def quit_called?;    @quit;              end
    def display;         @display ||= StubDisplay.new(@appended); end
    def appended_texts;  @appended.map(&:first);                  end
    def debug_snapshot
      { context_state: "{}", spinner_started_at: "nil", breath_supported: "true" }
    end
    def debug_tick_count;  5; end
    def debug_curses_caps
      { term: "test", colors: 256, color_pairs: 256, can_change_color: true, defined_attrs: [] }
    end

    class StubDisplay
      def initialize(buf); @buf = buf; end
      def append(text, style: nil); @buf << [text, style]; end
      def raw_emit(_bytes); end  # noop in tests
    end
  end
end

class TestDebugCommandsOptInBaslash < Test::Unit::TestCase
  def test_default_off
    builder = Baslash::Builder.new
    refute builder.debug_commands_enabled?
  end

  def test_dsl_turns_on
    builder = Baslash::Builder.new
    builder.enable_debug_commands
    assert builder.debug_commands_enabled?
  end
end
