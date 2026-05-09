# frozen_string_literal: true

require_relative "display"
require_relative "state"

module Cclikesh
  class Context
    def initialize(tuple_space)
      @ts = tuple_space
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
