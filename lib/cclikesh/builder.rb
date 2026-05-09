# frozen_string_literal: true

module Cclikesh
  class Builder
    attr_reader :on_submit_handler, :slash_handlers

    def initialize
      @on_submit_handler = nil
      @slash_handlers = {}
    end

    def on_submit(&block)
      @on_submit_handler = block
    end

    def slash(name, &block)
      @slash_handlers[name.to_sym] = block
    end

    def slash_handler(name)
      @slash_handlers[name.to_sym]
    end
  end
end
