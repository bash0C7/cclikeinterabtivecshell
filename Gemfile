# frozen_string_literal: true

source "https://rubygems.org"

# Both cclikesh.gemspec and baslash.gemspec coexist during the rename
# (Tasks 1-13). Resolve to baslash explicitly. Task 13 will delete
# cclikesh.gemspec and this disambiguation becomes unnecessary.
gemspec name: "baslash"

gem "drb"
gem "rinda"

gem "informers", "~> 1.2"
gem "unicode-display_width", "~> 3.0"

group :development do
  # TODO Task 12: re-enable after renaming cclikesh-debug/ to baslash-debug/
  # gem "baslash-debug", path: "baslash-debug"
  gem "cclikesh-debug", path: "cclikesh-debug"
  gem "extralite", "~> 2.12"
end
