# frozen_string_literal: true

module Baslash
  module Style
    NAMED_COLORS = {
      black:   30, red:     31, green:   32, yellow:  33,
      blue:    34, magenta: 35, cyan:    36, white:   37
    }.freeze

    NAMED_STYLES = {
      bold:      1,
      dim:       2,
      italic:    3,
      underline: 4,
      reverse:   7
    }.freeze

    # Application-semantic style names. The framework emits status/meta text
    # using these symbolic names; this table maps each name to one or more
    # SGR codes. NOTE: :result is intentionally absent — impl execution
    # output (stdout) should stay in the user's default terminal color, so
    # it falls through Style.apply unstyled.
    SEMANTIC_STYLES = {
      ok:       [32],     # green - success status
      ng:       [31],     # red - failure status
      error:    [31],     # red - error messages
      warn:     [33],     # yellow - warnings
      thinking: [2, 36],  # dim cyan - in-progress live slot
      meta:     [2, 36]   # dim cyan - framework metadata
    }.freeze

    def self.bold(text);     wrap(NAMED_STYLES[:bold],      text); end
    def self.dim(text);      wrap(NAMED_STYLES[:dim],       text); end
    def self.italic(text);   wrap(NAMED_STYLES[:italic],    text); end
    def self.underline(text); wrap(NAMED_STYLES[:underline], text); end

    def self.color(name, text)
      code = NAMED_COLORS[name]
      return text.to_s if code.nil?
      wrap(code, text)
    end

    def self.apply(name, text)
      return text.to_s if name.nil?
      codes =
        if SEMANTIC_STYLES.key?(name)
          SEMANTIC_STYLES[name]
        elsif NAMED_STYLES.key?(name)
          [NAMED_STYLES[name]]
        elsif NAMED_COLORS.key?(name)
          [NAMED_COLORS[name]]
        end
      return text.to_s if codes.nil?
      "\e[#{codes.join(';')}m#{text}\e[0m"
    end

    def self.strip(text)
      text.to_s.gsub(/\e\[[0-9;]*m/, "")
    end

    def self.wrap(code, text)
      "\e[#{code}m#{text}\e[0m"
    end
    private_class_method :wrap
  end
end
