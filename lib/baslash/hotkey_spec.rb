# frozen_string_literal: true

module Baslash
  class HotkeyError < StandardError; end

  module HotkeySpec
    CTRL_LETTER = /\AC-([a-zA-Z])\z/i.freeze
    META_LETTER = /\AM-([a-zA-Z0-9])\z/i.freeze

    def self.parse(spec)
      raise HotkeyError, "hotkey spec must be a non-empty String" unless spec.is_a?(String) && !spec.empty?
      tokens = spec.split(/\s+/)
      raise HotkeyError, "hotkey spec is empty after splitting" if tokens.empty?
      tokens.flat_map { |t| parse_token(t) }
    end

    def self.parse_token(tok)
      if (m = CTRL_LETTER.match(tok))
        ch = m[1].downcase.ord
        [ch - 96]
      elsif (m = META_LETTER.match(tok))
        [27, m[1].ord]
      else
        raise HotkeyError, "invalid hotkey token: #{tok.inspect}"
      end
    end
  end
end
