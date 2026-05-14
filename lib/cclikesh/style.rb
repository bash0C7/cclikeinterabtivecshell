# frozen_string_literal: true

module Cclikesh
  module Style
    # Built-in style names map to a small SGR vocabulary. fg accepts a basic
    # 30-37 color code OR a 256-color index (handled in sgr_pair). attr_only
    # is a single SGR parameter (e.g. 2 for dim).
    BUILTIN = {
      result:   { fg: 32 },        # green
      error:    { fg: 31 },        # red
      thinking: { fg: 35 },        # magenta
      dim:      { attr_only: 2 },  # dim
      gray:     { attr_only: 2 },  # alias of dim
    }

    @custom = {}
    @pairs  = {}

    def self.init!
      @custom = {}
      @pairs  = {}
      BUILTIN.each_key { |name| ensure_pair(name, BUILTIN[name]) }
    end

    def self.define(name, fg: nil, bg: nil, bold: false, dim: false, italic: false, underline: false, reverse: false)
      spec = { fg: fg, bg: bg, bold: bold, dim: dim, italic: italic, underline: underline, reverse: reverse }.compact
      @custom[name.to_sym] = spec
      ensure_pair(name, spec)
    end

    def self.lookup(name)
      key = name&.to_sym
      info = @pairs[key]
      return [nil, nil] unless info
      [info[:on], info[:off]]
    end

    def self.with(target, name)
      on, off = lookup(name)
      target.write(on) if on
      yield
    ensure
      target.write(off) if off
    end

    def self.ensure_pair(name, spec)
      key = name.to_sym
      return @pairs[key] if @pairs.key?(key)
      on, off = sgr_pair(spec)
      @pairs[key] = { on: on, off: off }
    end

    # Build the (open, close) SGR pair from a spec hash. Returns [nil, nil]
    # when the spec produces no visual change.
    def self.sgr_pair(spec)
      params = []
      params << 1 if spec[:bold]
      params << 2 if spec[:dim] || spec[:attr_only] == 2
      params << 3 if spec[:italic]
      params << 4 if spec[:underline]
      params << 7 if spec[:reverse]
      if (fg = spec[:fg])
        params << ((30..37).cover?(fg) ? fg : "38;5;#{fg}")
      end
      if (bg = spec[:bg])
        params << ((40..47).cover?(bg) ? bg : "48;5;#{bg}")
      end
      return [nil, nil] if params.empty?
      ["\e[#{params.join(';')}m", "\e[0m"]
    end
  end
end
