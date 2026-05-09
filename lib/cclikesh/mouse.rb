# frozen_string_literal: true

module Cclikesh
  module Mouse
    ENABLE  = "\e[?1000h\e[?1003h\e[?1006h"
    DISABLE = "\e[?1006l\e[?1003l\e[?1000l"

    SGR_RE = /\A\e\[<(\d+);(\d+);(\d+)([Mm])/

    Event = Struct.new(:button, :x, :y, :type)

    BUTTON_NAMES = {
      0  => :left,
      1  => :middle,
      2  => :right,
      64 => :wheel_up,
      65 => :wheel_down
    }.freeze

    def self.enable(io = $stdout)
      return unless io.respond_to?(:tty?) && io.tty?
      io.write(ENABLE)
      io.flush
    end

    def self.disable(io = $stdout)
      return unless io.respond_to?(:tty?) && io.tty?
      io.write(DISABLE)
      io.flush
    end

    def self.parse(seq)
      m = seq.to_s.match(SGR_RE)
      return nil unless m
      button = m[1].to_i
      x      = m[2].to_i
      y      = m[3].to_i
      release_or_press = m[4]
      type =
        if release_or_press == "m"
          :release
        elsif (64..67).cover?(button)
          :wheel
        else
          :press
        end
      Event.new(button_name(button), x, y, type)
    end

    def self.osc52_copy(io, text)
      return unless io.respond_to?(:tty?) && io.tty?
      io.write("\e]52;c;#{base64_encode(text)}\a")
      io.flush
    end

    B64_CHARS = (("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + ["+", "/"]).freeze

    def self.base64_encode(text)
      bytes = text.to_s.bytes
      out = +""
      bytes.each_slice(3) do |chunk|
        n = (chunk[0] || 0) << 16 | (chunk[1] || 0) << 8 | (chunk[2] || 0)
        out << B64_CHARS[(n >> 18) & 0x3f]
        out << B64_CHARS[(n >> 12) & 0x3f]
        out << (chunk.size >= 2 ? B64_CHARS[(n >> 6) & 0x3f] : "=")
        out << (chunk.size >= 3 ? B64_CHARS[n & 0x3f]        : "=")
      end
      out
    end

    def self.button_name(code)
      BUTTON_NAMES[code] || code
    end
  end
end
