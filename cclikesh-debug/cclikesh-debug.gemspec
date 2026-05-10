require_relative "lib/cclikesh/debug/version"

Gem::Specification.new do |s|
  s.name    = "cclikesh-debug"
  s.version = Cclikesh::Debug::VERSION
  s.authors = ["bash0C7"]
  s.summary = "cclikesh debug recording + viewer (per-session SQLite + sqlite-vec semantic + asciinema export)"
  s.license = "MIT"
  s.required_ruby_version = ">= 4.0.0"

  s.files       = Dir["lib/**/*.rb", "exe/cclikesh-debug"]
  s.bindir      = "exe"
  s.executables = ["cclikesh-debug"]
  s.require_paths = ["lib"]

  s.add_dependency "cclikesh",   ">= 0.2"
  s.add_dependency "sqlite3",    "~> 2.0"
  s.add_dependency "sqlite-vec", "~> 0.1"
  s.add_dependency "informers",  "~> 1.2"

  s.add_development_dependency "test-unit", "~> 3.6"
  s.add_development_dependency "rake",      "~> 13.0"
end
