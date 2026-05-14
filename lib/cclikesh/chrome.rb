# frozen_string_literal: true

require "curses"
require "unicode/display_width"
require_relative "style"

module Cclikesh
  module Chrome
    # No header window: header content is appended into the body at boot
    # by Runner.run, so the top of the alt-screen is just the body pad.
    FOOTER_HEIGHT = 3
    # Two-glyph blink (asterisk/plus) — picked over braille after the user
    # reported the braille rotation read as static on his terminals. With
    # only two distinct shapes alternating at ~200 ms, the motion is
    # unmistakably "blinking" rather than "spinning".
    SPINNER_GLYPHS = %w[* +].freeze
    SPINNER_FRAME_MS = 200

    # Per-char "bright cell" sweep cadence across the info_bar text. One
    # column advance per SWEEP_STEP_MS, cycling. 200 ms matches the
    # right-to-left bright cell observed on Claude Code's prompt echo.
    SWEEP_STEP_MS = 200

    # Two-color orange sweep on the info_bar, mirroring the bright-cell
    # wave observed on Claude Code's thinking line. We use the
    # terminal's standard 256-color palette directly rather than
    # OSC 4 / init_color — palette redefines are silently ignored on
    # many terminals (the user's setup did so), but stock 256-color
    # entries render the same on every 256-color terminal.
    #
    #   ORANGE_BRIGHT_FG = 209  # xterm 256-color #ff875f (255,135,95)
    #   ORANGE_DIM_FG    = 173  # xterm 256-color #d7875f (215,135,95)
    #
    # Pair ids 200/201 stay clear of Style's pair_id range (1..N).
    ORANGE_BRIGHT_FG    = 209
    ORANGE_DIM_FG       = 173
    ORANGE_BRIGHT_INDEX = 200
    ORANGE_DIM_INDEX    = 201

    class << self
      attr_reader :footer_win, :spinner_started_at, :breath_supported
      attr_accessor :winsize_dirty
    end

    def self.init
      @footer_win = Curses::Window.new(FOOTER_HEIGHT, Curses.cols,
                                        Curses.lines - FOOTER_HEIGHT, 0)
      @spinner_started_at = nil
      @winsize_dirty = false
      setup_breath_colors
      draw_dividers
    end

    # Allocate the two orange curses color pairs used by the sweep,
    # using stock 256-color palette indices (no OSC 4 redefine). Falls
    # back gracefully when the terminal has no color support; the sweep
    # then paints in the terminal's default fg and the wave isn't
    # visible (still better than ncurses raising).
    def self.setup_breath_colors
      @breath_supported = false
      return unless Curses.respond_to?(:has_colors?) && Curses.has_colors?
      Curses.init_pair(ORANGE_BRIGHT_INDEX, ORANGE_BRIGHT_FG, -1)
      Curses.init_pair(ORANGE_DIM_INDEX,    ORANGE_DIM_FG,    -1)
      @breath_supported = true
    rescue StandardError
      @breath_supported = false
    end

    def self.bright_attr
      @breath_supported ? Curses.color_pair(ORANGE_BRIGHT_INDEX) : 0
    end

    def self.dim_attr
      @breath_supported ? Curses.color_pair(ORANGE_DIM_INDEX) : 0
    end

    def self.close
      @footer_win&.close
      @footer_win = nil
    end

    def self.update_footer(info_bar:, status_rows:, shortcuts_hint:, phase: nil)
      return unless @footer_win
      # erase (werase) clears the window buffer without setting clearok,
      # so ncurses emits a per-cell diff on the next doupdate instead of
      # \e[H\e[2J (full screen). Full-screen clear was bleeding through
      # the prompt row managed by Reline, causing `> a` flicker.
      @footer_win.erase
      # row 0: spinner + info_bar segments
      @footer_win.setpos(0, 0)
      @footer_win.addstr(spinner_glyph(phase) + " ")
      info_text = info_bar.map { |item| item[:text] || item["text"] }.compact.join(" · ")
      info_truncated = truncate_to_width(info_text, Curses.cols - 4)
      draw_info_bar_with_sweep(info_truncated, phase)
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
      # Reline.readmultiline writes raw escape sequences into rows it
      # treats as its input territory; when input grows past the prompt
      # row, those writes physically overwrite the divider and footer
      # cells. Curses's internal cell cache still thinks those cells are
      # clean, so without an explicit touch + draw_dividers each tick,
      # the chrome never comes back even after the user backspaces the
      # newlines away. Touch is cheap (3 rows * cols) and we already pay
      # for one doupdate per periodic_tick.
      @footer_win.touch
      @footer_win.noutrefresh
      draw_dividers
    end

    # Paint info_bar text in dim orange, with one cell highlighted in
    # bright orange that sweeps one column per SWEEP_STEP_MS while a
    # working phase is active. Mirrors Claude Code's bright-cell sweep
    # observed on its prompt echo (see tmp/longrun/pty_claude_thinking
    # capture memo for the source palette).
    def self.draw_info_bar_with_sweep(text, phase)
      sweep = sweep_position(phase, text.length)
      if sweep.nil?
        @footer_win.addstr(text)
        return
      end
      bright = bright_attr
      dim    = dim_attr
      text.each_char.with_index do |ch, i|
        attrs = i == sweep ? bright : dim
        if attrs != 0
          @footer_win.attron(attrs); @footer_win.addstr(ch); @footer_win.attroff(attrs)
        else
          @footer_win.addstr(ch)
        end
      end
    end

    # Index of the character currently rendered in bright orange (the
    # sweeping cell), or nil when no sweep is active (phase != :working,
    # no spinner start time yet, or empty text).
    def self.sweep_position(phase, len)
      return nil unless phase == :working
      return nil unless @spinner_started_at
      return nil if len <= 0
      elapsed_ms = (Time.now - @spinner_started_at) * 1000
      (elapsed_ms / SWEEP_STEP_MS).to_i % len
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
      return unless @footer_win
      @footer_win.resize(FOOTER_HEIGHT, Curses.cols)
      @footer_win.move(Curses.lines - FOOTER_HEIGHT, 0)
      Curses.stdscr.clear
      draw_dividers
      Display.refresh if defined?(Display) && Display.respond_to?(:refresh)
      Curses.doupdate
    end

    # Draw two full-width horizontal rules on stdscr:
    #   - below the body  (separates body from prompt)
    #   - below the prompt (separates prompt from footer)
    # The body fills from row 0 down to the body/prompt divider; header
    # content lives inside the body and scrolls with it.
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
