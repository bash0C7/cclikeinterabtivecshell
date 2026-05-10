# frozen_string_literal: true

require "curses"
require "unicode/display_width"
require_relative "style"

module Cclikesh
  module Chrome
    HEADER_HEIGHT = 3
    FOOTER_HEIGHT = 3
    SPINNER_GLYPHS = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    class << self
      attr_reader :header_win, :footer_win, :spinner_index
    end

    def self.init
      @header_win = Curses::Window.new(HEADER_HEIGHT, Curses.cols, 0, 0)
      @footer_win = Curses::Window.new(FOOTER_HEIGHT, Curses.cols,
                                        Curses.lines - FOOTER_HEIGHT - 1, 0)
      @spinner_index = 0
    end

    def self.close
      @header_win&.close
      @footer_win&.close
      @header_win = nil
      @footer_win = nil
    end

    def self.update_header(lines)
      return unless @header_win
      @header_win.clear
      lines.each_with_index do |line, i|
        next if i >= HEADER_HEIGHT
        @header_win.setpos(i, 0)
        @header_win.addstr(truncate_to_width(line.to_s, Curses.cols - 1))
      end
      @header_win.noutrefresh
    end

    def self.update_footer(info_bar:, status_rows:, shortcuts_hint:)
      return unless @footer_win
      @footer_win.clear
      # row 0: spinner + info_bar segments
      @footer_win.setpos(0, 0)
      glyph = SPINNER_GLYPHS[@spinner_index % SPINNER_GLYPHS.size]
      @footer_win.addstr(glyph + " ")
      info_text = info_bar.map { |item| item[:text] || item["text"] }.compact.join(" · ")
      @footer_win.addstr(truncate_to_width(info_text, Curses.cols - 4))
      # row 1: status_rows
      @footer_win.setpos(1, 0)
      status_text = status_rows.flat_map do |r|
        segs = r[:segments] || r["segments"] || []
        segs.map { |s| s[:text] || s["text"] || "" }
      end.join(" · ")
      @footer_win.addstr(truncate_to_width(status_text, Curses.cols - 1))
      # row 2: shortcuts hint
      @footer_win.setpos(2, 0)
      Style.with(@footer_win, :dim) do
        @footer_win.addstr(truncate_to_width(shortcuts_hint.to_s, Curses.cols - 1))
      end
      @footer_win.noutrefresh
    end

    def self.tick_spinner(phase)
      return unless phase == :working
      @spinner_index = (@spinner_index + 1) % SPINNER_GLYPHS.size
    end

    def self.handle_resize
      return unless @header_win && @footer_win
      @header_win.resize(HEADER_HEIGHT, Curses.cols)
      @footer_win.resize(FOOTER_HEIGHT, Curses.cols)
      @footer_win.move(Curses.lines - FOOTER_HEIGHT - 1, 0)
    end

    def self.truncate_to_width(s, max_cols)
      return s if Unicode::DisplayWidth.of(s) <= max_cols
      acc = +""
      w = 0
      s.each_grapheme_cluster do |g|
        gw = Unicode::DisplayWidth.of(g)
        break if w + gw > max_cols - 1
        acc << g
        w += gw
      end
      acc + "…"
    end
  end
end
