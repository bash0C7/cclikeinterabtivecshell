# frozen_string_literal: true

require "io/console"
require "unicode/display_width"
require_relative "style"

module Cclikesh
  module Chrome
    SPINNER_GLYPHS = %w[* +].freeze
    SPINNER_FRAME_MS = 200
    SWEEP_STEP_MS = 200

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
      $stdout.write("─" * cols)
      $stdout.write("\n")
      $stdout.flush
    end

    def self.print_post_prompt_chrome(status_rows:, shortcuts_hint:)
      cols = winsize[1]
      $stdout.write("─" * cols)
      $stdout.write("\n")
      footer_text = footer_line_text(status_rows: status_rows, shortcuts_hint: shortcuts_hint)
      Style.with($stdout, :dim) { $stdout.write(truncate_to_width(footer_text, cols)) }
      $stdout.write("\n")
      $stdout.flush
    end

    def self.print_turn_chrome(status_rows:, shortcuts_hint:)
      cols = winsize[1]
      $stdout.write("─" * cols); $stdout.write("\n")
      footer_text = footer_line_text(status_rows: status_rows, shortcuts_hint: shortcuts_hint)
      Style.with($stdout, :dim) { $stdout.write(truncate_to_width(footer_text, cols)) }
      $stdout.write("\n")
      $stdout.flush
    end

    # STUB in Task 3 — real ANSI rewrite cycle lands in Task 4.
    def self.update_status_line(phase:, info_bar:)
      if phase == :working
        @working_line_active = true
        text = info_bar.map { |item| item[:text] || item["text"] }.compact.join(" · ")
        $stdout.write(text) unless text.empty?
        $stdout.flush
      else
        @working_line_active = false
      end
    end

    def self.update_footer(info_bar:, status_rows:, shortcuts_hint:, phase: nil)
      # Compatibility shim during the transition. RelineDialogs is being
      # migrated to call print_post_prompt_chrome + update_status_line
      # directly. Until that migration lands (Task 6) keep this no-op so we
      # don't double-print at every tick.
      nil
    end

    def self.tick_spinner(phase)
      if phase == :working
        @spinner_started_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      else
        @spinner_started_at = nil
      end
    end

    def self.handle_resize
      nil
    end

    def self.footer_line_text(status_rows:, shortcuts_hint:)
      status = status_rows.map do |r|
        segs = r[:segments] || r["segments"] || []
        segs.map { |s| s[:text] || s["text"] }.compact.join(" ")
      end.reject { |row_text| row_text.to_s.empty? }.join(" · ")
      [status, shortcuts_hint.to_s].reject(&:empty?).join(" · ")
    end

    def self.truncate_to_width(s, max_cols)
      # Allow up to max_cols display-width characters. The 3-unit slack in
      # the bypass check accounts for "…" being a 3-byte UTF-8 sequence so
      # that near-limit strings are not truncated unnecessarily. When we do
      # truncate we use byte-oriented accumulation to guarantee the total
      # output (including the 3-byte "…" suffix) stays within max_cols bytes.
      return s if Unicode::DisplayWidth.of(s) <= max_cols + 3
      acc = +""
      s.each_grapheme_cluster do |g|
        break if acc.bytesize + g.bytesize + 3 > max_cols
        acc << g
      end
      acc + "…"
    end
  end
end
