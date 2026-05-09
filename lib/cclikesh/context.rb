# frozen_string_literal: true

require "drb/drb"
require_relative "display"
require_relative "state"

module Cclikesh
  class Context
    include DRb::DRbUndumped

    def initialize(tuple_space, registry: nil)
      @ts = tuple_space
      @registry = registry
    end

    def logger
      raise "Context has no registry; cannot provide logger" unless @registry
      @registry.logger
    end

    def display
      @display ||= Display.new(@ts)
    end

    def state
      @state ||= State.new(@ts)
    end

    def quit
      @ts.write([:cmd, :quit])
      @ts.write([:key, nil])
    end
  end
end
