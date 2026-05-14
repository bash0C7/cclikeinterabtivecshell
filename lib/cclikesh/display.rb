# frozen_string_literal: true

require "unicode/display_width"
require_relative "style"
require_relative "transcript"

module Cclikesh
  module Display
    class << self
      attr_reader :current_slot
    end

    def self.init
      @current_slot = nil
      @next_sid = 0
    end

    def self.close
      @current_slot = nil
      @next_sid = 0
    end

    def self.append(text, prompt: nil, style: nil)
      rendered = "#{prompt}#{text}"
      Style.with($stdout, style) { $stdout.write(rendered) }
      $stdout.write("\n")
      $stdout.flush
      Transcript.record(rendered)
    end

    # Opens a "live" line: we write a placeholder newline so the cursor sits on
    # a row dedicated to this slot, then each live_update rewinds and rewrites
    # that row. Opening a new slot auto-commits any previous slot.
    def self.open_live(style: nil)
      auto_commit_previous
      sid = (@next_sid += 1)
      @current_slot = { sid: sid, last_text: "", style: style, committed: false }
      $stdout.write("\n")  # reserve the row
      $stdout.flush
      sid
    end

    def self.live_update(sid, text)
      slot = @current_slot
      return if slot.nil? || slot[:sid] != sid || slot[:committed]
      rewrite_current_line(text, slot[:style])
      slot[:last_text] = text
    end

    def self.live_commit(sid, final = nil)
      slot = @current_slot
      return if slot.nil? || slot[:sid] != sid || slot[:committed]
      text = final || slot[:last_text]
      rewrite_current_line(text, slot[:style])
      Transcript.record(text)
      slot[:committed] = true
      @current_slot = nil
    end

    def self.live_discard(sid)
      slot = @current_slot
      return if slot.nil? || slot[:sid] != sid || slot[:committed]
      $stdout.write("\e[1A\r\e[K\n")
      $stdout.flush
      slot[:committed] = true
      @current_slot = nil
    end

    def self.dialog(content, style: nil)
      lines = content.to_s.split("\n", -1)
      lines.pop if lines.last == ""
      width = (lines.map { |l| Unicode::DisplayWidth.of(l) }.max || 0) + 2
      append("┌#{"─" * width}┐", style: :dim)
      lines.each do |line|
        pad_n = [width - 2 - Unicode::DisplayWidth.of(line), 0].max
        append("│ #{line}#{" " * pad_n} │", style: style)
      end
      append("└#{"─" * width}┘", style: :dim)
    end

    def self.live_slot_state
      slot = @current_slot
      return {} unless slot && !slot[:committed]
      { slot[:sid] => { row: nil, last_text: slot[:last_text], style: slot[:style] } }
    end

    def self.rewrite_current_line(text, style)
      $stdout.write("\e[1A\r\e[K")
      Style.with($stdout, style) { $stdout.write(text) }
      $stdout.write("\n")
      $stdout.flush
    end

    def self.auto_commit_previous
      slot = @current_slot
      return unless slot && !slot[:committed]
      Transcript.record(slot[:last_text]) unless slot[:last_text].empty?
      slot[:committed] = true
      @current_slot = nil
    end
  end
end
