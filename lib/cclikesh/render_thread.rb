# frozen_string_literal: true

require_relative "renderer"
require_relative "footer"
require_relative "header"
require_relative "input_box"
require "rinda/tuplespace"

module Cclikesh
  class RenderThread
    FOOTER_PAINT_INTERVAL_S = 0.25

    def self.start(ts, output_io, tick_interval: 0.06, registry: nil, ctx: nil)
      Thread.new do
        renderer = Renderer.new(ts, output_io, registry: registry)
        stopping = false
        last_footer_paint = Time.now - FOOTER_PAINT_INTERVAL_S
        watcher = Thread.new do
          ts.read([:cmd, :quit])
          stopping = true
          ts.write([:cmd, :refresh])
        end
        until stopping
          refreshed = false
          begin
            ts.take([:cmd, :refresh], tick_interval)
            refreshed = true
          rescue Rinda::RequestExpiredError
            # normal tick — no refresh signal arrived
          end
          renderer.render_pending
          if refreshed
            paint_chrome(output_io, registry)
          end
          if refreshed || (Time.now - last_footer_paint) >= FOOTER_PAINT_INTERVAL_S
            paint_footer(output_io, registry, ctx)
            last_footer_paint = Time.now
          end
          output_io.flush
        end
        renderer.render_pending
        paint_footer(output_io, registry, ctx)
        output_io.flush
        watcher.kill
      end
    end

    def self.paint_chrome(io, registry)
      return unless io.respond_to?(:tty?) && io.tty?
      return unless registry
      lines = registry.header_lines
      Layout.save_cursor(io)
      Header.paint(io, lines, cols: Layout.cols) if lines && !lines.empty?
      InputBox.paint(io, Layout.cols)
      Layout.restore_cursor(io)
    rescue StandardError
      # never let chrome paint kill the render loop
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
