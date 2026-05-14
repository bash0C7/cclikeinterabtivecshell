# frozen_string_literal: true

require_relative "lib/cclikesh/version"

Gem::Specification.new do |spec|
  spec.name          = "cclikesh"
  spec.version       = Cclikesh::VERSION
  spec.authors       = ["bash0C7"]
  spec.summary       = "Claude Code-style 3-region interactive CLI shell framework (curses + Ractor)"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "curses",                "~> 1.4"
  spec.add_dependency "reline",                "~> 0.6"
  spec.add_dependency "unicode-display_width", "~> 3.0"
  spec.add_dependency "logger"

  spec.add_development_dependency "test-unit", "~> 3.6"
  spec.add_development_dependency "rake",      "~> 13.0"
  spec.add_development_dependency "irb",       "~> 1.18"
end
