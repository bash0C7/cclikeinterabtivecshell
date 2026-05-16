require_relative "lib/baslash/debug/version"

Gem::Specification.new do |s|
  s.name    = "baslash-debug"
  s.version = Baslash::Debug::VERSION
  s.authors = ["bash0C7"]
  s.summary = "baslash debug recording + viewer (per-session SQLite + sqlite-vec semantic + asciinema export)"
  s.license = "MIT"
  s.required_ruby_version = ">= 4.0.0"

  s.files       = Dir["lib/**/*.rb", "exe/baslash-debug", "exe/baslash-debug-embedder"]
  s.bindir      = "exe"
  s.executables = ["baslash-debug", "baslash-debug-embedder"]
  s.require_paths = ["lib"]

  s.add_dependency "baslash",   ">= 0.2"
  s.add_dependency "extralite",  "~> 2.12"
  s.add_dependency "sqlite-vec", "~> 0.1"
  s.add_dependency "informers",  "~> 1.2"
  s.add_dependency "drb"

  s.add_development_dependency "test-unit", "~> 3.6"
  s.add_development_dependency "rake",      "~> 13.0"
end
