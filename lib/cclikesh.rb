# frozen_string_literal: true

# Make the vendored ts4r available as `require "ts4r"`.
$LOAD_PATH.unshift(File.expand_path("../vendor", __dir__))

require_relative "cclikesh/version"
require_relative "cclikesh/runner"

module Cclikesh
  def self.run(input_path:, output_path:, tick_interval: 0.06, &block)
    Runner.run(input_path: input_path, output_path: output_path, tick_interval: tick_interval, &block)
  end
end
