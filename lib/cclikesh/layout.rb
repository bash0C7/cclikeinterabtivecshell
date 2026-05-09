# frozen_string_literal: true

require_relative "screen"

module Cclikesh
  module Layout
    @rows          = 24
    @cols          = 80
    @header_height = 0
    @input_height  = 1
    @footer_height = 0

    class << self
      attr_reader :rows, :cols, :header_height, :input_height, :footer_height
    end

    def self.recompute(rows: nil, cols: nil, header_height: nil, input_height: nil, footer_height: nil)
      @rows          = rows          if rows
      @cols          = cols          if cols
      @header_height = header_height if header_height
      @input_height  = input_height  if input_height
      @footer_height = footer_height if footer_height
    end

    def self.update_from_io(io)
      r, c = Screen.size(io)
      recompute(rows: r, cols: c)
    end

    def self.header_top;     1                                                        end
    def self.header_bottom;  @header_height                                           end
    def self.history_top;    @header_height + 1                                       end
    def self.history_bottom; [@rows - @input_height - @footer_height, history_top].max end
    def self.input_top;      history_bottom + 1                                       end
    def self.input_bottom;   input_top + @input_height - 1                            end
    def self.footer_top;     input_bottom + 1                                         end
    def self.footer_bottom;  @rows                                                    end

    def self.position(io, row, col = 1)
      io.write("\e[#{row};#{col}H")
    end

    def self.clear_line(io)
      io.write("\e[2K")
    end

    def self.set_scroll_region(io)
      top = history_top
      bot = history_bottom
      return if top > bot
      io.write("\e[#{top};#{bot}r")
    end

    def self.reset_scroll_region(io)
      io.write("\e[r")
    end

    def self.save_cursor(io)
      io.write("\e[s")
    end

    def self.restore_cursor(io)
      io.write("\e[u")
    end

    def self.in_history(io)
      return yield unless io.respond_to?(:tty?) && io.tty?
      save_cursor(io)
      position(io, history_bottom)
      yield
    ensure
      restore_cursor(io) if io.respond_to?(:tty?) && io.tty?
    end
  end
end
