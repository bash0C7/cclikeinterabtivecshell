# frozen_string_literal: true

require "timeout"
require_relative "test_helper"
require "baslash/slash_registry"
require "baslash/slash_dispatcher"

class TestSlashDispatcherBaslash < Test::Unit::TestCase
  def setup
    @reg = Baslash::SlashRegistry.new
    @reg.register(:echo, proc { |args, ctx| ctx.display.append(args.join(" ")) }, description: "echo")
  end

  def test_handle_slash_command_dispatches
    main = Ractor.current
    Baslash::SlashDispatcher.handle("/echo hi there", @reg, main, on_submit: nil, state_refs: {})
    msg = wait_for_msg(2.0)
    assert_equal :append, msg[0]
    assert_equal "hi there", msg[1]
  end

  def test_handle_unknown_slash_sends_error_append
    main = Ractor.current
    Baslash::SlashDispatcher.handle("/nope", @reg, main, on_submit: nil, state_refs: {})
    msg = wait_for_msg(2.0)
    assert_equal :append, msg[0]
    assert_match(/Unknown command/, msg[1])
  end

  def test_handle_non_slash_uses_on_submit
    on_submit = Ractor.shareable_proc { |args, ctx| ctx.display.append("submit: #{args.first}") }
    main = Ractor.current
    Baslash::SlashDispatcher.handle("plain text", @reg, main, on_submit: on_submit, state_refs: {})
    msg = wait_for_msg(2.0)
    assert_equal "submit: plain text", msg[1]
  end

  def test_handle_bare_slash_is_noop
    main = Ractor.current
    assert_nothing_raised do
      Baslash::SlashDispatcher.handle("/", @reg, main, on_submit: nil, state_refs: {})
    end
    # No message should be emitted — the user was browsing the slash menu
    # and dismissed without picking, so we don't want an "Unknown command"
    # error or any other output.
    assert_no_msg(0.2)
  end

  def test_handle_slash_with_only_whitespace_is_noop
    main = Ractor.current
    assert_nothing_raised do
      Baslash::SlashDispatcher.handle("/   ", @reg, main, on_submit: nil, state_refs: {})
    end
    assert_no_msg(0.2)
  end

  private

  def wait_for_msg(secs)
    Timeout.timeout(secs) { Ractor.receive }
  end

  def assert_no_msg(secs)
    assert_raise(Timeout::Error) do
      Timeout.timeout(secs) { Ractor.receive }
    end
  end
end
