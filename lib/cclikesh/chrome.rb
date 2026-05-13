# frozen_string_literal: true

require "curses"
require "unicode/display_width"
require_relative "style"

module Cclikesh
  module Chrome
    HEADER_HEIGHT = 3
    FOOTER_HEIGHT = 3
    SPINNER_GLYPHS = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
    # Per-frame cadence in milliseconds. ~105ms ≈ 9.5 fps, matching the
    # Claude Code thinking spinner. The actual rendered cadence is bounded
    # by the Reline periodic_tick rate (see RelineDialogs.install), so the
    # observed motion will be the slower of the two.
    SPINNER_FRAME_MS = 105

    # Uniform-grey "breathing" wave applied to the info_bar text while a
    # working phase is active. 32 greys from RGB 153..184 (matching the
    # palette observed on Claude Code's thinking word), triangle-wave
    # over BREATH_PERIOD_MS. Indices 200..231 in the curses color table —
    # chosen above Style's pair_id range (1..N) to avoid collision.
    BREATH_COLOR_BASE = 200
    BREATH_STEPS = 32
    BREATH_GREY_MIN = 153
    BREATH_PERIOD_MS = 2100

    class << self
      attr_reader :header_win, :footer_win, :spinner_started_at
    end

    def self.init
      @header_win = Curses::Window.new(HEADER_HEIGHT, Curses.cols, 0, 0)
      @footer_win = Curses::Window.new(FOOTER_HEIGHT, Curses.cols,
                                        Curses.lines - FOOTER_HEIGHT, 0)
      @spinner_started_at = nil
      setup_breath_colors
      draw_dividers
    end

    # Allocate the 32 grey curses color pairs used by breath_color_pair.
    # Falls back gracefully when the terminal can't redefine colors
    # (e.g. macOS Terminal.app); breath_color_pair then returns nil and
    # update_footer paints the info_bar with the terminal's default fg.
    def self.setup_breath_colors
      @breath_supported = false
      return unless Curses.respond_to?(:can_change_color?) && Curses.can_change_color?
      BREATH_STEPS.times do |i|
        grey = BREATH_GREY_MIN + i
        rgb_milli = grey * 1000 / 255
        Curses.init_color(BREATH_COLOR_BASE + i, rgb_milli, rgb_milli, rgb_milli)
        Curses.init_pair(BREATH_COLOR_BASE + i, BREATH_COLOR_BASE + i, -1)
      end
      @breath_supported = true
    rescue StandardError
      @breath_supported = false
    end

    # Triangle-wave grey color pair tied to wall-clock since the working
    # phase began. Returns nil when not in :working, when the spinner
    # hasn't started yet, or when the terminal can't redefine colors.
    def self.breath_color_pair(phase)
      return nil unless @breath_supported
      return nil unless phase == :working
      return nil unless @spinner_started_at
      elapsed_ms = (Time.now - @spinner_started_at) * 1000
      phase_pos = (elapsed_ms % BREATH_PERIOD_MS) / BREATH_PERIOD_MS.to_f
      level = phase_pos < 0.5 ? phase_pos * 2 : (1.0 - phase_pos) * 2
      idx = (level * (BREATH_STEPS - 1)).round.clamp(0, BREATH_STEPS - 1)
      Curses.color_pair(BREATH_COLOR_BASE + idx)
    end

    def self.close
      @header_win&.close
      @footer_win&.close
      @header_win = nil
      @footer_win = nil
    end

    def self.update_header(lines)
      return unless @header_win
      # erase (werase) clears the window buffer without setting clearok,
      # so ncurses emits a per-cell diff on the next doupdate instead of
      # \e[H\e[2J (full screen). Full-screen clear was bleeding through
      # the prompt row managed by Reline, causing `> a` flicker.
      @header_win.erase
      lines.each_with_index do |line, i|
        next if i >= HEADER_HEIGHT
        @header_win.setpos(i, 0)
        @header_win.addstr(truncate_to_width(line.to_s, Curses.cols - 1))
      end
      @header_win.noutrefresh
    end

    def self.update_footer(info_bar:, status_rows:, shortcuts_hint:, phase: nil)
      return unless @footer_win
      # See update_header for why erase (werase) is used instead of clear.
      @footer_win.erase
      # row 0: spinner + info_bar segments
      @footer_win.setpos(0, 0)
      @footer_win.addstr(spinner_glyph(phase) + " ")
      info_text = info_bar.map { |item| item[:text] || item["text"] }.compact.join(" · ")
      info_truncated = truncate_to_width(info_text, Curses.cols - 4)
      breath = breath_color_pair(phase)
      if breath
        @footer_win.attron(breath)
        @footer_win.addstr(info_truncated)
        @footer_win.attroff(breath)
      else
        @footer_win.addstr(info_truncated)
      end
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

    # tick_spinner is invoked once per periodic_tick to mark whether a
    # working phase is active. The actual glyph chosen for each repaint
    # is derived from the elapsed wall-clock since the working phase
    # began (see spinner_glyph), so the user perceives smooth rotation
    # even if periodic_tick fires irregularly.
    def self.tick_spinner(phase)
      if phase == :working
        @spinner_started_at ||= Time.now
      else
        @spinner_started_at = nil
      end
    end

    def self.spinner_glyph(phase)
      return SPINNER_GLYPHS.first unless phase == :working
      @spinner_started_at ||= Time.now
      frame = ((Time.now - @spinner_started_at) * 1000 / SPINNER_FRAME_MS).to_i
      SPINNER_GLYPHS[frame % SPINNER_GLYPHS.size]
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
