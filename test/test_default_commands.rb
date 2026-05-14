# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/slash_registry"
require "cclikesh/default_commands"

class TestDefaultCommands < Test::Unit::TestCase
  def setup
    @registry = Cclikesh::SlashRegistry.new
    Cclikesh::DefaultCommands.register(@registry)
  end

  def test_exit_command_registered
    refute_nil @registry.lookup(:exit)
  end

  def test_q_command_registered
    refute_nil @registry.lookup(:q)
  end

  def test_help_command_registered
    refute_nil @registry.lookup(:help)
  end

  def test_exit_body_calls_ctx_quit
    ctx = build_ctx
    @registry.lookup(:exit)[:body].call([], ctx)
    assert ctx.quit_called?
  end

  def test_help_body_lists_each_registered_entry
    ctx = build_ctx
    @registry.lookup(:help)[:body].call([], ctx)
    appended = ctx.appended_texts
    assert(appended.any? { |t| t.include?("/exit") }, "expected /exit in help, got: #{appended.inspect}")
    assert(appended.any? { |t| t.include?("/q") },    "expected /q in help, got: #{appended.inspect}")
    assert(appended.any? { |t| t.include?("/help") }, "expected /help in help, got: #{appended.inspect}")
  end

  private

  def build_ctx
    StubCtx.new
  end

  class StubCtx
    def initialize
      @quit = false
      @appended = []
    end

    def quit
      @quit = true
    end

    def quit_called?
      @quit
    end

    def display
      @display ||= StubDisplay.new(@appended)
    end

    def appended_texts
      @appended.map(&:first)
    end

    class StubDisplay
      def initialize(buf)
        @buf = buf
      end

      def append(text, style: nil)
        @buf << [text, style]
      end
    end
  end
end
