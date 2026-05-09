# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class State
    include DRb::DRbUndumped

    def initialize(tuple_space)
      @ts = tuple_space
      @cache = {}
      @mutex = Mutex.new
    end

    def [](key)
      @mutex.synchronize { @cache[key.to_sym] }
    end

    def []=(key, value)
      sym = key.to_sym
      old, changed = @mutex.synchronize do
        prev = @cache[sym]
        @cache[sym] = value
        [prev, prev != value]
      end
      @ts.write([:state, sym, value])
      @ts.write([:event, :state_change, sym, old, value]) if changed
    end

    def delete(key)
      sym = key.to_sym
      old, existed = @mutex.synchronize do
        had = @cache.key?(sym)
        prev = @cache.delete(sym)
        [prev, had]
      end
      return nil unless existed
      @ts.write([:event, :state_change, sym, old, nil])
      old
    end

    def update(hash)
      hash.each { |k, v| self[k] = v }
      self
    end

    def to_h
      @mutex.synchronize { @cache.dup }
    end
  end
end
