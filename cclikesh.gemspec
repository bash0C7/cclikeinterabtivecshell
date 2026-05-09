# frozen_string_literal: true

require_relative "lib/cclikesh/version"

Gem::Specification.new do |spec|
  spec.name          = "cclikesh"
  spec.version       = Cclikesh::VERSION
  spec.authors       = ["bash0C7"]
  spec.summary       = "Claude Code-style 3-region interactive CLI shell framework"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files         = Dir["lib/**/*.rb", "vendor/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # ts4r is vendored at vendor/ts4r.rb; no runtime gem dependency on it yet.
  # rinda was removed from Ruby's default gems in 3.4+, but vendor/ts4r.rb
  # requires "rinda/tuplespace", so we declare it as a runtime dependency.
  spec.add_dependency "rinda", "~> 0.2"

  spec.add_development_dependency "test-unit", "~> 3.6"
  spec.add_development_dependency "rake", "~> 13.0"
end
