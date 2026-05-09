# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class Dialog
    include DRb::DRbUndumped

    def initialize(display)
      @display = display
    end

    def show(content, style: nil)
      lines = content.to_s.split("\n", -1)
      lines.pop if lines.last == ""
      width = (lines.map(&:length).max || 0) + 2

      @display.append("┌#{"─" * width}┐", style: :dim)
      lines.each do |line|
        padded = line.ljust(width - 2)
        @display.append("│ #{padded} │", style: style)
      end
      @display.append("└#{"─" * width}┘", style: :dim)
    end

    def close
      nil
    end
  end
end
