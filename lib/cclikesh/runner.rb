# frozen_string_literal: true

require "drb/drb"
require "drb/unix"
require_relative "drb_patches"
require "reline"
require_relative "tuple_space"
require_relative "builder"
require_relative "context"
require_relative "dispatcher"
require_relative "handler_registry"
require_relative "forking"
require_relative "render_thread"
require_relative "input_thread"

module Cclikesh
  class Runner
    def self.run(tick_interval: 0.06, &block)
      builder = Builder.new
      block.call(builder)
      registry = HandlerRegistry.new(builder)

      Forking.run(registry) do |handlers_uri|
        run_child(handlers_uri, tick_interval: tick_interval)
      end
    end

    def self.run_child(handlers_uri, tick_interval:)
      DRb.start_service
      registry_remote = DRbObject.new_with_uri(handlers_uri)

      ts = TupleSpace.new
      ctx = Context.new(ts)
      dispatcher = Dispatcher.new(ts, registry_remote, ctx)

      render_thread = RenderThread.start(ts, $stdout,
                                         tick_interval: tick_interval,
                                         registry: registry_remote)
      input_thread  = InputThread.start(ts, reader: Reline.method(:readline), prompt: "> ")

      loop do
        break if dispatcher.dispatch_one == :quit
      end

      ts.write([:cmd, :quit])
      render_thread.join(2)
      input_thread.join(2)
      DRb.stop_service
    end
  end
end
