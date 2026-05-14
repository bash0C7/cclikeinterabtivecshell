# frozen_string_literal: true

require "curses"
require "unicode/display_width"
require_relative "style"
require_relative "transcript"
require_relative "chrome"

module Cclikesh
  module Display
    PAD_HEIGHT = 10_000

    class << self
      attr_reader :pad
    end

    def self.init
      @pad = Curses::Pad.new(PAD_HEIGHT, Curses.cols)
      @pad.scrollok(true)
      @row = 0
      @live_slots = {}
      @next_sid = 0
    end

    def self.close
      @pad&.close
      @pad = nil
      @live_slots = {}
    end

    def self.append(text, prompt: nil, style: nil)
      rendered = "#{prompt}#{text}"
      @pad.setpos(@row, 0)
      Style.with(@pad, style) do
        @pad.addstr(rendered)
      end
      @row += 1
      Transcript.record(rendered)
      refresh
    end

    def self.open_live(style: nil)
      sid = (@next_sid += 1)
      @live_slots[sid] = { row: @row, last_text: "", style: style }
      @pad.setpos(@row, 0)
      @row += 1
      sid
    end

    def self.live_update(sid, text)
      slot = @live_slots[sid] or return
      @pad.setpos(slot[:row], 0)
      @pad.clrtoeol
      Style.with(@pad, slot[:style]) { @pad.addstr(text) }
      slot[:last_text] = text
      refresh
    end

    def self.live_commit(sid, final = nil)
      slot = @live_slots.delete(sid) or return
      text = final || slot[:last_text]
      @pad.setpos(slot[:row], 0)
      @pad.clrtoeol
      Style.with(@pad, slot[:style]) { @pad.addstr(text) }
      Transcript.record(text)
      refresh
    end

    def self.live_discard(sid)
      slot = @live_slots.delete(sid) or return
      @pad.setpos(slot[:row], 0)
      @pad.clrtoeol
      @row -= 1 if slot[:row] == @row - 1
      refresh
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
      @live_slots.dup
    end

    def self.refresh
      return unless @pad
      # Body fills from the top of the alt-screen down to the body/prompt
      # divider.  All row indices are 0-based (curses convention).
      #   body_top    = 0  (no header window — header is appended to the
      #                     body as regular content at boot)
      #   body_bottom = lines - FOOTER_HEIGHT - 4
      #                 (row just above the body/prompt divider at lines-F-3)
      body_top    = 0
      body_bottom = Curses.lines - Chrome::FOOTER_HEIGHT - 4
      visible_h   = body_bottom - body_top + 1
      return if visible_h <= 0
      visible_top = [@row - visible_h, 0].max
      bottom_col  = Curses.cols - 1
      return if bottom_col < 0
      @pad.noutrefresh(visible_top, 0,
                       body_top, 0,
                       body_bottom, bottom_col)
    end
  end
end
