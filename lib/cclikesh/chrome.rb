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
                                        Curses.lines - FOOTER_HEIGHT, 0)
      @spinner_index = 0
      draw_dividers
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
      status_text = status_rows.map do |r|
        segs = r[:segments] || r["segments"] || []
        segs.map { |s| s[:text] || s["text"] }.compact.join(" ")
      end.reject { |row_text| row_text.to_s.empty? }.join(" · ")
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
      @footer_win.move(Curses.lines - FOOTER_HEIGHT, 0)
      Curses.stdscr.clear
      draw_dividers
    end

    # Draw three full-width horizontal rules on stdscr:
    #   - below the header (separates header from body)
    #   - below the body  (separates body from prompt)
    #   - below the prompt (separates prompt from footer)
    def self.draw_dividers
      width = Curses.cols
      # Use the alternate-character-set horizontal line (ACS 'q' = 0x71) via
      # addch so we work on byte-oriented ncurses (macOS system ncurses 6.0
      # without wide-char support) where addstr("─" * cols) only renders the
      # leftmost cell due to the 3-byte UTF-8 encoding being treated as raw
      # bytes. A_ALTCHARSET | 0x71 renders as ─ on ACS-capable terminals and
      # as - otherwise, without relying on addch looping over multi-byte chars.
      acs_hline = Curses::A_ALTCHARSET | 0x71
      [
        HEADER_HEIGHT,                            # below header
        Curses.lines - FOOTER_HEIGHT - 3,         # below body (above prompt)
        Curses.lines - FOOTER_HEIGHT - 1          # below prompt (above footer)
      ].each do |row|
        Curses.stdscr.setpos(row, 0)
        width.times { Curses.stdscr.addch(acs_hline) }
      end
      Curses.stdscr.noutrefresh
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
