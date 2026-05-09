# frozen_string_literal: true

require_relative "cclikesh/version"
require_relative "cclikesh/runner"

module Cclikesh
  def self.run(&block)
    Runner.run(&block)
  end
end
