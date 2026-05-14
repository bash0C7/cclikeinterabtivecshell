# frozen_string_literal: true

require "reline"
require "reline/io/ansi"

# Reline's main input loop calls Reline::ANSI#inner_getc(timeout) which
# polls @input.wait_readable(0.01) until either input arrives or the
# timeout expires. When there is no pending input the top-level read_io
# passes Float::INFINITY, so the polling loop runs forever and the
# spinner / footer never animate until the user hits a key.
#
# This patch hooks the 10ms wait_readable loop and invokes a registered
# callback at most once per IDLE_TICK_INTERVAL seconds. Concurrency is
# kept on the main Ractor (no Thread.new — cclikesh forbids that via
# test/test_thread_zero.rb), so callers don't need locking around
# shared state in line-mode.
module Cclikesh
  module RelineIdlePatch
    IDLE_TICK_INTERVAL = 0.1  # seconds between idle-tick callbacks
    TICK_HISTORY_WINDOW = 5.0

    @tick_history = []

    class << self
      attr_accessor :callback
      attr_reader :tick_history
    end

    def self.record_tick(now)
      @tick_history << now
      cutoff = now - TICK_HISTORY_WINDOW
      @tick_history.shift while !@tick_history.empty? && @tick_history.first < cutoff
    end
  end
end

class Reline::ANSI
  alias_method :inner_getc_without_cclikesh_tick, :inner_getc

  def inner_getc(timeout_second)
    unless @buf.empty?
      return @buf.shift
    end
    cb = Cclikesh::RelineIdlePatch.callback
    last_tick = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    until @input.wait_readable(0.01)
      timeout_second -= 0.01
      return nil if timeout_second <= 0
      Reline.core.line_editor.handle_signal
      if cb
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now - last_tick >= Cclikesh::RelineIdlePatch::IDLE_TICK_INTERVAL
          cb.call
          Cclikesh::RelineIdlePatch.record_tick(now)
          last_tick = now
        end
      end
    end
    c = @input.getbyte

    # When "Escape non-ASCII Input with Control-V" is enabled in macOS
    # Terminal.app, all non-ascii bytes are automatically escaped with
    # `C-v`. "\xE3\x81\x82" (U+3042) becomes "\x16\xE3\x16\x81\x16\x82".
    (c == 0x16 && @input.tty? && @input.raw(min: 0, time: 0, &:getbyte)) || c
  rescue Errno::EIO
    # Maybe the I/O has been closed.
    nil
  end
end
