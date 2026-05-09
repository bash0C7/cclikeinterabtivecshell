# frozen_string_literal: true

require_relative "tuple_space"
require_relative "builder"
require_relative "context"
require_relative "dispatcher"
require_relative "render_ractor"
require_relative "input_ractor"

module Cclikesh
  class Runner
    def self.run(input_path:, output_path:, tick_interval: 0.06, &block)
      builder = Builder.new
      block.call(builder)

      ts = TupleSpace.new
      ctx = Context.new(ts)
      dispatcher = Dispatcher.new(ts, builder, ctx)

      render_ractor = RenderRactor.start(ts, output_path, tick_interval: tick_interval)
      InputRactor.start(ts, input_path)

      loop do
        break if dispatcher.dispatch_one == :quit
      end

      ts.write([:cmd, :quit])
      render_ractor.value rescue nil
    end
  end
end
