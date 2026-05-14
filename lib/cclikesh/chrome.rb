# frozen_string_literal: true

require "io/console"
require "unicode/display_width"
require_relative "style"

module Cclikesh
  module Chrome
    SPINNER_GLYPHS = %w[* +].freeze
    SPINNER_FRAME_MS = 200
    SWEEP_STEP_MS = 200

    # Cursor offset (rows above the prompt) for the status_line row. The
    # layout is fixed:
    #   ...output...
    #   <status_line>          ← N=2 rows above the prompt
    #   ─────────              ← divider 1, N=1
    #   > _                    ← prompt cursor anchor (N=0)
    STATUS_LINE_ROWS_ABOVE_PROMPT = 2

    class << self
      attr_reader :spinner_started_at
    end

    def self.init
      @spinner_started_at = nil
      @working_line_active = false
    end

    def self.close
      @working_line_active = false
    end

    def self.working_line_active?
      @working_line_active ? true : false
    end

    def self.winsize
      io = IO.console
      return [24, 80] unless io
      io.winsize
    rescue StandardError
      [24, 80]
    end

    def self.print_pre_prompt_divider
      cols = winsize[1]
      $stdout.write("─" * (cols - 1))
      $stdout.write("\r\n")
      $stdout.flush
    end

    def self.print_post_prompt_chrome(status_rows:, shortcuts_hint:)
      cols = winsize[1]
      $stdout.write("─" * (cols - 1))
      $stdout.write("\r\n")
      footer_text = footer_line_text(status_rows: status_rows, shortcuts_hint: shortcuts_hint)
      Style.with($stdout, :dim) { $stdout.write(truncate_to_width(footer_text, cols)) }
      $stdout.write("\r\n")
      $stdout.flush
    end

    def self.update_status_line(phase:, info_bar:)
      cols = winsize[1]
      if phase == :working
        text = info_bar.map { |item| item[:text] || item["text"] }.compact.join(" · ")
        rendered = truncate_to_width(spinner_glyph(phase) + " " + text, cols)
        emit_status_rewrite(rendered)
        @working_line_active = true
      elsif @working_line_active
        emit_status_rewrite("")
        @working_line_active = false
      end
    end

    def self.emit_status_rewrite(text)
      $stdout.write("\e7")                              # save
      $stdout.write("\e[#{STATUS_LINE_ROWS_ABOVE_PROMPT}A")  # up N rows
      $stdout.write("\r\e[K")                           # CR + erase line
      $stdout.write(text)
      $stdout.write("\e8")                              # restore
      $stdout.flush
    end

    def self.spinner_glyph(phase)
      return SPINNER_GLYPHS.first unless phase == :working
      @spinner_started_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @spinner_started_at) * 1000
      SPINNER_GLYPHS[(elapsed / SPINNER_FRAME_MS).to_i % SPINNER_GLYPHS.size]
    end

    def self.tick_spinner(phase)
      if phase == :working
        @spinner_started_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      else
        @spinner_started_at = nil
      end
    end

    def self.footer_line_text(status_rows:, shortcuts_hint:)
      status = status_rows.map do |r|
        segs = r[:segments] || r["segments"] || []
        segs.map { |s| s[:text] || s["text"] }.compact.join(" ")
      end.reject { |row_text| row_text.to_s.empty? }.join(" · ")
      [status, shortcuts_hint.to_s].reject(&:empty?).join(" · ")
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
