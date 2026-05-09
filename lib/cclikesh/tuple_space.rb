# frozen_string_literal: true

require "ts4r"

module Cclikesh
  class TupleSpace
    def self.new
      Ractor.make_shareable(TupleSpace4Ractor.new)
    end
  end
end
