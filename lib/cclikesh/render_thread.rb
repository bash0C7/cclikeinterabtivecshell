# frozen_string_literal: true

require_relative "renderer"
require "rinda/tuplespace"

module Cclikesh
  class RenderThread
    def self.start(ts, output_io, tick_interval: 0.06, registry: nil)
      Thread.new do
        renderer = Renderer.new(ts, output_io, registry: registry)
        stopping = false
        watcher = Thread.new do
          ts.read([:cmd, :quit])
          stopping = true
          ts.write([:cmd, :refresh])
        end
        until stopping
          begin
            ts.take([:cmd, :refresh], tick_interval)
          rescue Rinda::RequestExpiredError
            # normal tick — no refresh signal arrived
          end
          renderer.render_pending
          output_io.flush
        end
        renderer.render_pending
        output_io.flush
        watcher.kill
      end
    end
  end
end
