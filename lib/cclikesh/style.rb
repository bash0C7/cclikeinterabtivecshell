# frozen_string_literal: true

module Cclikesh
  module Style
    BUILTINS = {
      default:  nil,
      result:   { fg: :green },
      error:    { fg: :red },
      prompt:   { fg: :cyan },
      thinking: { fg: :magenta },
      dim:      { dim: true }
    }.freeze

    FG_CODES = {
      black: 30, red: 31, green: 32, yellow: 33,
      blue: 34, magenta: 35, cyan: 36, white: 37
    }.freeze

    def self.wrap(text, name, custom: nil)
      spec = custom || BUILTINS[name&.to_sym]
      return text if spec.nil? || spec.empty?

      codes = []
      codes << 1 if spec[:bold]
      codes << 2 if spec[:dim]
      codes << FG_CODES[spec[:fg]] if spec[:fg] && FG_CODES.key?(spec[:fg])
      return text if codes.empty?

      "\e[#{codes.join(';')}m#{text}\e[0m"
    end
  end
end
