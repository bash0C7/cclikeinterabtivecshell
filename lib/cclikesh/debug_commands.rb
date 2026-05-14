# frozen_string_literal: true

module Cclikesh
  module DebugCommands
    # Pure-function escape interpreter for /debug-emit. Translates a
    # Ruby-style escape string into raw bytes without using eval. Only
    # the explicit escapes listed below are recognized; everything else
    # raises ArgumentError. Bytes pass through untouched.
    #
    # Recognized escapes:
    #   \e          → 0x1b (ESC)
    #   \n \r \t    → 0x0a 0x0d 0x09
    #   \\          → 0x5c (single backslash)
    #   \xNN        → byte N (exactly 2 hex digits, 0-9a-fA-F)
    #   anything else after a backslash → ArgumentError
    module EscapeInterpreter
      def self.parse(input)
        out = String.new(encoding: Encoding::ASCII_8BIT)
        i = 0
        bytes = input.b
        len = bytes.bytesize
        while i < len
          c = bytes.byteslice(i, 1)
          if c == "\\"
            raise ArgumentError, "trailing backslash" if i + 1 >= len
            n = bytes.byteslice(i + 1, 1)
            case n
            when "e" then out << "\x1b".b; i += 2
            when "n" then out << "\x0a".b; i += 2
            when "r" then out << "\x0d".b; i += 2
            when "t" then out << "\x09".b; i += 2
            when "\\" then out << "\x5c".b; i += 2
            when "x"
              hex = bytes.byteslice(i + 2, 2)
              raise ArgumentError, "incomplete \\x escape" if hex.nil? || hex.bytesize < 2
              raise ArgumentError, "non-hex digits in \\x escape: #{hex.inspect}" unless hex =~ /\A[0-9a-fA-F]{2}\z/
              out << hex.to_i(16).chr.b
              i += 4
            else
              raise ArgumentError, "unknown escape \\#{n}"
            end
          else
            out << c
            i += 1
          end
        end
        out
      end
    end
  end
end
