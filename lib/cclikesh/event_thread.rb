# frozen_string_literal: true

require "rinda/tuplespace"

module Cclikesh
  class EventThread
    def self.start(ts, registry:, ctx:)
      Thread.new do
        loop do
          quit_tuple = begin
            ts.read([:cmd, :quit], 0)
          rescue Rinda::RequestExpiredError
            nil
          end

          if quit_tuple
            drain_remaining_state_changes(ts, registry, ctx)
            break
          end

          begin
            _, _, key, old, new_v = ts.take([:event, :state_change, nil, nil, nil], 0.05)
            registry.dispatch_state_change(key, old, new_v, ctx)
          rescue Rinda::RequestExpiredError
            # tick
          end
        end
      end
    end

    def self.drain_remaining_state_changes(ts, registry, ctx)
      loop do
        _, _, key, old, new_v = ts.take([:event, :state_change, nil, nil, nil], 0)
        registry.dispatch_state_change(key, old, new_v, ctx)
      end
    rescue Rinda::RequestExpiredError
      # done draining
    end
  end
end
