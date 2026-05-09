# frozen_string_literal: true

require_relative "layout"

module Cclikesh
  module InputBox
    HEIGHT = 3
    PROMPT = "│ > "

    def self.height; HEIGHT; end
    def self.prompt; PROMPT; end

    def self.paint(io, cols)
      return unless io.respond_to?(:tty?) && io.tty?
      bar_w = [cols - 2, 1].max
      top    = "╭" + ("─" * bar_w) + "╮"
      bottom = "╰" + ("─" * bar_w) + "╯"

      Layout.save_cursor(io)
      Layout.position(io, Layout.input_top, 1)
      Layout.clear_line(io)
      io.write(top)
      Layout.position(io, Layout.input_bottom, 1)
      Layout.clear_line(io)
      io.write(bottom)
      Layout.restore_cursor(io)
      io.flush if io.respond_to?(:flush)
    end
  end
end
