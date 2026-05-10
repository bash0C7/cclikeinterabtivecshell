# frozen_string_literal: true

module Cclikesh
  class SlashRegistry
    def initialize
      @entries = {}
    end

    def register(name, body, description: nil)
      shareable_body = Ractor.shareable_proc(&body)
      @entries[name.to_sym] = {
        body:        shareable_body,
        description: description.to_s.freeze
      }.freeze
    end

    def lookup(name)
      @entries[name.to_sym]
    end

    def each(&block)
      @entries.each(&block)
    end

    def all
      @entries.dup.freeze
    end
  end
end
