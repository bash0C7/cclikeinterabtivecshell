# frozen_string_literal: true

module Cclikesh
  module Screen
    ALT_ENTER = "\e[?1049h\e[H"
    ALT_LEAVE = "\e[?1049l"

    def self.enter_alt(io = $stdout)
      return unless io.tty?
      io.write(ALT_ENTER)
      io.flush
    end

    def self.leave_alt(io = $stdout)
      return unless io.tty?
      io.write(ALT_LEAVE)
      io.flush
    end

    def self.size(io = $stdout)
      return [24, 80] unless io.tty?
      io.winsize
    rescue
      [24, 80]
    end
  end
end
