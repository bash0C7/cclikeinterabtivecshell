# frozen_string_literal: true

require_relative "renderer"

module Cclikesh
  class RenderRactor
    # Spawns a Ractor that periodically renders pending tuples from `ts` to
    # the file at `output_path` (opened in append mode inside the Ractor).
    # The Ractor terminates when [:cmd, :quit] is observed.
    def self.start(ts, output_path, tick_interval: 0.06)
      Ractor.new(ts, output_path, tick_interval) do |ts, output_path, tick_interval|
        require "cclikesh/renderer"
        File.open(output_path, "a") do |out|
          renderer = Cclikesh::Renderer.new(ts, out)
          frame_id = 0
          stopping = false
          # Quit watcher thread inside this Ractor — blocks on read,
          # flips `stopping` when quit is written.
          watcher = Thread.new do
            ts.read([:cmd, :quit])
            stopping = true
          end
          loop do
            break if stopping
            sleep tick_interval
            renderer.render_pending
            out.flush
            frame_id += 1
            ts.write([:rendered, frame_id])
          end
          watcher.kill
        end
      end
    end
  end
end
