# frozen_string_literal: true

require "rinda/tuplespace"

module Cclikesh
  class TupleSpace
    # Use a short keeper period so wildcard-template timeouts (e.g. in
    # EventThread#take) are signalled promptly by the Rinda keeper thread.
    # The default period of 60s causes blocking take calls with nil wildcards
    # to hang far beyond their requested timeout.
    KEEPER_PERIOD = 0.05

    def self.new
      Rinda::TupleSpace.new(KEEPER_PERIOD)
    end
  end
end
