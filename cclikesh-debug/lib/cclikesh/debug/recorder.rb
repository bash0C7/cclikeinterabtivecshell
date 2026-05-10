require "json"
require_relative "storage"
require_relative "content_builder"

module Cclikesh
  module Debug
    class Recorder
      def initialize(storage:, embedder_factory:, no_vector: false)
        @storage = storage
        @embedder = no_vector ? nil : embedder_factory.call
        @synthetic = []
      end

      def synthetic_frame!(ts:, content:, framework_state:)
        @synthetic << { ts: ts, content: content, framework_state: framework_state }
      end

      def drain_one_cycle!
        @synthetic.each do |f|
          fid = @storage.insert_frame(
            ts: f[:ts], trigger: "on_demand", event_kind: nil,
            cursor_row: 0, cursor_col: 0,
            raw_bytes_zlib: nil,
            framework_state_json: f[:framework_state].to_json,
            content: f[:content],
            source: "framework_state"
          )
          if @embedder
            vec = @embedder.embed(f[:content])
            @storage.upsert_frame_vec(fid, vec)
          end
        end
        @synthetic.clear
      end

      def stop!
        # Placeholder for future Ractor pipeline cleanup (Task 27).
      end
    end
  end
end
