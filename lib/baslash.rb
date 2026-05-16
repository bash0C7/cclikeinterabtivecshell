# frozen_string_literal: true

require_relative "baslash/version"

module Baslash
  def self.run(&block)
    raise NotImplementedError, "Baslash.run is wired in Task 10 (Runner)"
  end
end
