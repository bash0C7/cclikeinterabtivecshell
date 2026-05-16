# frozen_string_literal: true

require "test/unit"
require "stringio"
require "logger"
require "baslash/slash_dispatcher"
require "baslash/slash_registry"
require "baslash/display"
require "baslash/context"

class TestSlashDispatcherBaslash < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::Display.reset_for_test
    Baslash::Context.init(logger: Logger.new(IO::NULL))
    @registry = Baslash::SlashRegistry.new
    @registry.register(:hello, ->(_args, ctx) {
      ctx.display.append("hi from hello")
    })
    @registry.register(:boom, ->(_args, _ctx) { raise "kaboom" })
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_dispatch_slash_command_runs_body
    Baslash::SlashDispatcher.handle("/hello a b", @registry, on_submit: nil, state_refs: {}, logger: nil)
    assert_includes $stdout.string, "hi from hello"
  end

  def test_dispatch_unknown_command_prints_error
    Baslash::SlashDispatcher.handle("/unknown", @registry, on_submit: nil, state_refs: {}, logger: nil)
    assert_includes $stdout.string, "Unknown command: /unknown"
  end

  def test_dispatch_bare_slash_is_noop
    Baslash::SlashDispatcher.handle("/", @registry, on_submit: nil, state_refs: {}, logger: nil)
    refute_includes $stdout.string, "Unknown"
  end

  def test_dispatch_slash_with_only_whitespace_is_noop
    Baslash::SlashDispatcher.handle("/   ", @registry, on_submit: nil, state_refs: {}, logger: nil)
    refute_includes $stdout.string, "Unknown"
  end

  def test_dispatch_non_slash_calls_on_submit
    received = nil
    on_submit = ->(args, ctx) { received = args.first; ctx.display.append("submitted: #{received}") }
    Baslash::SlashDispatcher.handle("plain text", @registry, on_submit: on_submit, state_refs: {}, logger: nil)
    assert_equal "plain text", received
    assert_includes $stdout.string, "submitted: plain text"
  end

  def test_dispatch_non_slash_without_on_submit_is_noop
    Baslash::SlashDispatcher.handle("plain text", @registry, on_submit: nil, state_refs: {}, logger: nil)
    assert_empty $stdout.string
  end

  def test_dispatch_rescues_handler_exceptions
    Baslash::SlashDispatcher.handle("/boom", @registry, on_submit: nil, state_refs: {}, logger: Baslash::Context.logger)
    assert_includes $stdout.string, "Handler failed"
    assert_includes $stdout.string, "kaboom"
  end

  def test_dispatch_rescues_interrupt
    @registry.register(:slow, ->(_args, _ctx) { raise Interrupt })
    Baslash::SlashDispatcher.handle("/slow", @registry, on_submit: nil, state_refs: {}, logger: nil)
    assert_includes $stdout.string, "^C"
  end
end
