# frozen_string_literal: true

require "drb/drb"
require_relative "display"
require_relative "state"
require_relative "dialog"

module Cclikesh
  class Context
    include DRb::DRbUndumped

    def initialize(tuple_space, registry: nil)
      @ts = tuple_space
      @registry = registry
    end

    def display
      @display ||= Display.new(@ts)
    end

    def state
      @state ||= State.new(@ts)
    end

    def dialog
      @dialog ||= Dialog.new(display)
    end

    def logger
      raise "Context has no registry; cannot provide logger" unless @registry
      @registry.logger
    end

    def quit
      @ts.write([:key, nil])
    end

    def refresh
      @ts.write([:cmd, :refresh])
    end
  end
end
