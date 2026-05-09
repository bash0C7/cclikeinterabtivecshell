# frozen_string_literal: true

require_relative "cclikesh/version"
require_relative "cclikesh/runner"
require_relative "cclikesh/event_thread"
require_relative "cclikesh/info_bar"

module Cclikesh
  def self.run(&block)
    Runner.run(&block)
  end
end
