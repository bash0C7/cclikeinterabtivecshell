# frozen_string_literal: true

require "unicode/display_width"
require_relative "style"
require_relative "transcript"

module Baslash
  # Body content renderer. Writes lines directly to stdout so that the
  # terminal's natural scroll moves old rows into native scrollback.
  # Live slots are single-line in-place updates via CR + EL (\r\e[K) and
  # do not consume scrollback until committed.
  module Display
    @next_sid = 0
    @live_open = {}

    class << self
      def append(text, style: nil)
        line = Style.apply(style, text)
        $stdout.puts(line)
        $stdout.flush
        Transcript.record(text.to_s) if defined?(Baslash::Transcript)
      end

      def open_live(style: nil)
        sid = (@next_sid += 1)
        @live_open[sid] = { style: style, last: "" }
        sid
      end

      def live_update(sid, text)
        slot = @live_open[sid]
        return if slot.nil?
        slot[:last] = text.to_s
        $stdout.print("\r\e[K\e[1G\e[0m#{render_live(slot[:style], text)}")
        $stdout.flush
      end

      def live_commit(sid, final = nil)
        slot = @live_open.delete(sid)
        return if slot.nil?
        text = (final.nil? ? slot[:last] : final).to_s
        $stdout.print("\r\e[K\e[1G\e[0m#{render_live(slot[:style], text)}")
        $stdout.puts
        $stdout.flush
        Transcript.record(text) if defined?(Baslash::Transcript)
      end

      def live_discard(sid)
        @live_open.delete(sid)
        $stdout.print("\r\e[K")
        $stdout.flush
      end

      def dialog(content, style: nil)
        lines = content.to_s.split("\n", -1)
        lines.pop if lines.last == ""
        width = (lines.map { |l| Unicode::DisplayWidth.of(l) }.max || 0) + 2
        append("┌#{"─" * width}┐", style: :dim)
        lines.each do |line|
          pad_n = [width - 2 - Unicode::DisplayWidth.of(line), 0].max
          append("│ #{line}#{" " * pad_n} │", style: style)
        end
        append("└#{"─" * width}┘", style: :dim)
      end

      def reset_for_test
        @next_sid = 0
        @live_open.clear
      end

      private

      def render_live(style, text)
        if style.nil?
          "#{text}\e[0m"
        else
          Style.apply(style, text)
        end
      end
    end
  end
end
