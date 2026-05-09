# frozen_string_literal: true

module Cclikesh
  module Style
    BUILTINS = {
      default:   nil,
      result:    { fg: :green },
      error:     { fg: :red },
      prompt:    { fg: :cyan },
      thinking:  { fg: :magenta },
      dim:       { dim: true },
      slash_tag: { bg: 245, fg: 15, bold: true }
    }.freeze

    FG_CODES = {
      black: 30, red: 31, green: 32, yellow: 33,
      blue: 34, magenta: 35, cyan: 36, white: 37
    }.freeze

    BG_CODES = {
      black: 40, red: 41, green: 42, yellow: 43,
      blue: 44, magenta: 45, cyan: 46, white: 47
    }.freeze

    def self.wrap(text, name, custom: nil)
      spec = custom || BUILTINS[name&.to_sym]
      return text if spec.nil? || spec.empty?

      codes = []
      codes << 1 if spec[:bold]
      codes << 2 if spec[:dim]
      codes.concat(fg_codes(spec[:fg]))
      codes.concat(bg_codes(spec[:bg]))
      return text if codes.empty?

      "\e[#{codes.join(';')}m#{text}\e[0m"
    end

    def self.fg_codes(fg)
      return [] if fg.nil?
      return ["38;5;#{fg}"] if fg.is_a?(Integer)
      return [FG_CODES[fg]] if FG_CODES.key?(fg)
      []
    end

    def self.bg_codes(bg)
      return [] if bg.nil?
      return ["48;5;#{bg}"] if bg.is_a?(Integer)
      return [BG_CODES[bg]] if BG_CODES.key?(bg)
      []
    end
  end
end
