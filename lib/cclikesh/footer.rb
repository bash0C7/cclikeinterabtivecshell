# frozen_string_literal: true

require_relative "layout"
require_relative "style"

module Cclikesh
  module Footer
    LINK_COLORS = {
      green:  32, yellow: 33, red:    31,
      gray:   90, purple: 35, blue:   34
    }.freeze

    class Row
      attr_reader :segments

      def initialize
        @segments = []
      end

      def text(str, style: nil)
        @segments << wrap(str.to_s, style)
        self
      end

      def bar(percent:, width: 12, filled: "█", empty: "░", style: nil)
        pct = clamp(percent.to_f, 0, 100)
        f   = (width * pct / 100.0).round
        bar_str = (filled * f) + (empty * (width - f))
        @segments << wrap("#{bar_str} #{pct.round}%", style)
        self
      end

      def link(text:, state: :gray)
        color = LINK_COLORS[state] || LINK_COLORS[:gray]
        @segments << "\e[#{color};4m#{text}\e[0m"
        self
      end

      def icon(glyph, style: nil)
        @segments << wrap(glyph.to_s, style)
        self
      end

      def spinner(frame)
        @segments << Style.wrap(frame.to_s, :thinking)
        self
      end

      def to_line(separator: " · ")
        @segments.join(separator)
      end

      private

      def wrap(str, style)
        style.nil? ? str : Style.wrap(str, style)
      end

      def clamp(v, lo, hi)
        return lo if v < lo
        return hi if v > hi
        v
      end
    end

    def self.paint(io, lines)
      return if lines.nil? || lines.empty?
      lines.each_with_index do |line, idx|
        Layout.position(io, Layout.footer_top + idx, 1)
        Layout.clear_line(io)
        io.write(line) if line
      end
    end
  end
end
