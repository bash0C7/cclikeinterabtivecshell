# frozen_string_literal: true

require_relative "renderer"

module Cclikesh
  class RenderThread
    def self.start(ts, output_io, tick_interval: 0.06)
      Thread.new do
        renderer = Renderer.new(ts, output_io)
        stopping = false
        watcher = Thread.new do
          ts.read([:cmd, :quit])
          stopping = true
        end
        until stopping
          sleep tick_interval
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
