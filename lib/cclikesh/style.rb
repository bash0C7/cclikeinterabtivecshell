# frozen_string_literal: true

require "curses"

module Cclikesh
  module Style
    BUILTIN = {
      result:   { fg: Curses::COLOR_GREEN },
      error:    { fg: Curses::COLOR_RED },
      thinking: { fg: Curses::COLOR_MAGENTA },
      dim:      { attr_only: Curses::A_DIM },
      gray:     { attr_only: Curses::A_DIM },
    }

    @custom = {}
    @pairs  = {}
    @next_pair_id = 1

    def self.init!
      @custom = {}
      @pairs  = {}
      @next_pair_id = 1
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
      return [nil, 0] unless info
      [info[:pair], info[:attr]]
    end

    def self.with(window, name)
      pair, attr = lookup(name)
      composed = (pair || 0) | attr
      window.attron(composed) if composed != 0
      yield
    ensure
      window.attroff(composed) if composed && composed != 0
    end

    def self.ensure_pair(name, spec)
      key = name.to_sym
      return @pairs[key] if @pairs.key?(key)
      pair_id = nil
      if spec[:fg] || spec[:bg]
        pair_id = @next_pair_id
        @next_pair_id += 1
        Curses.init_pair(pair_id, spec[:fg] || -1, spec[:bg] || -1)
      end
      attr = 0
      attr |= Curses::A_BOLD      if spec[:bold]
      attr |= Curses::A_DIM       if spec[:dim] || spec[:attr_only] == Curses::A_DIM
      attr |= Curses::A_UNDERLINE if spec[:underline]
      attr |= Curses::A_REVERSE   if spec[:reverse]
      pair = pair_id ? Curses.color_pair(pair_id) : 0
      @pairs[key] = { pair: pair, attr: attr }
    end
  end
end
