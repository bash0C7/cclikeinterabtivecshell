# frozen_string_literal: true

require_relative "renderer"
require_relative "footer"
require "rinda/tuplespace"

module Cclikesh
  class RenderThread
    def self.start(ts, output_io, tick_interval: 0.06, registry: nil, ctx: nil)
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
          paint_footer(output_io, registry, ctx)
          output_io.flush
        end
        renderer.render_pending
        paint_footer(output_io, registry, ctx)
        output_io.flush
        watcher.kill
      end
    end

    def self.paint_footer(io, registry, ctx)
      return unless io.respond_to?(:tty?) && io.tty?
      return unless registry && ctx
      lines = registry.snapshot_footer(ctx)
      Layout.save_cursor(io)
      Footer.paint(io, lines)
      Layout.restore_cursor(io)
    rescue StandardError
      # never let footer paint kill the render loop
    end
  end
end
