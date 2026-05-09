# frozen_string_literal: true

# Make the vendored ts4r available as `require "ts4r"`.
$LOAD_PATH.unshift(File.expand_path("../vendor", __dir__))

require_relative "cclikesh/version"

module Cclikesh
end
