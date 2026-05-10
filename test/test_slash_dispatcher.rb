# frozen_string_literal: true

require "timeout"
require_relative "test_helper"
require "cclikesh/slash_registry"
require "cclikesh/slash_dispatcher"

class TestSlashDispatcher < Test::Unit::TestCase
  def setup
    @reg = Cclikesh::SlashRegistry.new
    @reg.register(:echo, proc { |args, ctx| ctx.display.append(args.join(" ")) }, description: "echo")
  end

  def test_handle_slash_command_dispatches
    main = Ractor.current
    Cclikesh::SlashDispatcher.handle("/echo hi there", @reg, main, on_submit: nil, state_refs: {})
    msg = wait_for_msg(2.0)
    assert_equal :append, msg[0]
    assert_equal "hi there", msg[1]
  end

  def test_handle_unknown_slash_sends_error_append
    main = Ractor.current
    Cclikesh::SlashDispatcher.handle("/nope", @reg, main, on_submit: nil, state_refs: {})
    msg = wait_for_msg(2.0)
    assert_equal :append, msg[0]
    assert_match(/Unknown command/, msg[1])
  end

  def test_handle_non_slash_uses_on_submit
    on_submit = Ractor.shareable_proc { |args, ctx| ctx.display.append("submit: #{args.first}") }
    main = Ractor.current
    Cclikesh::SlashDispatcher.handle("plain text", @reg, main, on_submit: on_submit, state_refs: {})
    msg = wait_for_msg(2.0)
    assert_equal "submit: plain text", msg[1]
  end

  private

  def wait_for_msg(secs)
    Timeout.timeout(secs) { Ractor.receive }
  end
end
