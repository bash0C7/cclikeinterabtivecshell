# frozen_string_literal: true

module Baslash
  class HotkeyError < StandardError; end

  module HotkeySpec
    CTRL_LETTER = /\AC-([a-zA-Z])\z/i.freeze
    META_LETTER = /\AM-([a-zA-Z0-9])\z/i.freeze

    # Byte sequences we refuse to bind because they are load-bearing in the
    # baslash UX: Ctrl-C interrupts a handler, Enter/LF submit, Tab opens the
    # slash menu / completion, Backspace deletes a char.
    RESERVED_BYTES = [
      [3],  # C-c SIGINT
      [13], # C-m CR / Enter
      [10], # C-j LF
      [9],  # C-i TAB
      [8]   # C-h backspace
    ].freeze

    def self.parse(spec)
      unless spec.is_a?(String) && !spec.strip.empty?
        raise HotkeyError, "hotkey spec must be a non-empty String, got #{spec.inspect}"
      end
      tokens = spec.split(/\s+/).reject(&:empty?)
      raise HotkeyError, "hotkey spec is empty after splitting: #{spec.inspect}" if tokens.empty?
      bytes = tokens.flat_map { |t| parse_token(t) }
      if RESERVED_BYTES.include?(bytes)
        raise HotkeyError, "hotkey #{spec.inspect} is reserved by baslash"
      end
      bytes
    end

    # Canonical form: "C-g", "M-d", "C-x C-r" — uppercase modifier, lowercase letter.
    def self.format(spec)
      tokens = spec.to_s.split(/\s+/).reject(&:empty?)
      tokens.map { |t| format_token(t) }.join(" ")
    end

    def self.parse_token(tok)
      if (m = CTRL_LETTER.match(tok))
        [m[1].downcase.ord - 96]
      elsif (m = META_LETTER.match(tok))
        ch = m[1]
        b = ch.match?(/[A-Z]/) ? ch.downcase.ord : ch.ord
        [27, b]
      else
        raise HotkeyError, "invalid hotkey token: #{tok.inspect}"
      end
    end

    def self.format_token(tok)
      if (m = CTRL_LETTER.match(tok))
        "C-#{m[1].downcase}"
      elsif (m = META_LETTER.match(tok))
        ch = m[1]
        ch = ch.downcase if ch.match?(/[A-Z]/)
        "M-#{ch}"
      else
        raise HotkeyError, "invalid hotkey token: #{tok.inspect}"
      end
    end
  end
end
