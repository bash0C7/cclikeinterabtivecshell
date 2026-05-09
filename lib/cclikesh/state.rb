# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class State
    include DRb::DRbUndumped

    def initialize(tuple_space)
      @ts = tuple_space
      @cache = {}
    end

    def [](key)
      @cache[key.to_sym]
    end

    def []=(key, value)
      sym = key.to_sym
      old = @cache[sym]
      @cache[sym] = value
      @ts.write([:state, sym, value])
      @ts.write([:event, :state_change, sym, old, value]) if old != value
    end
  end
end
