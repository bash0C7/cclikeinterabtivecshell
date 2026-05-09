# frozen_string_literal: true

require_relative "cclikesh/version"
require_relative "cclikesh/runner"
require_relative "cclikesh/event_thread"

module Cclikesh
  def self.run(&block)
    Runner.run(&block)
  end
end
