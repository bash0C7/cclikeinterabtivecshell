require "json"
require_relative "storage"
require_relative "content_builder"
require_relative "ractors/pty_reader"
require_relative "ractors/frame_builder"
require_relative "ractors/storage_writer"
require_relative "ractors/embedder_thread"

module Cclikesh
  module Debug
    class Recorder
      def initialize(storage:, embedder_factory:, no_vector: false)
        @storage = storage
        @embedder_factory = embedder_factory
        @embedder = no_vector ? nil : embedder_factory.call
        @no_vector = no_vector
        @synthetic = []
        @pty_reader = nil
        @frame_builder = nil
        @storage_writer = nil
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

      # Starts the 3-Ractor live pipeline:
      #   PtyReader → FrameBuilder → StorageWriter
      #
      # Embedding is intentionally excluded from the live pipeline because informers is not
      # Ractor-safe. Use embed_pending! after the session ends for batch embedding.
      #
      # DRb note: DRb cannot run inside a Ractor (shared state: DRb.current_server, etc.).
      # The orchestrator must pull debug_snapshot via DRb in the main thread and call
      # trigger_capture! which sends the pre-fetched snapshot to FrameBuilder.
      def start_pipeline!(pty_master_fd:)
        @storage_writer = Ractors::StorageWriter.spawn(
          db_path: @storage.path,
          embed_bridge: nil
        )
        @frame_builder = Ractors::FrameBuilder.spawn(
          downstream: @storage_writer
        )
        @pty_reader = Ractors::PtyReader.spawn(
          downstream: @frame_builder,
          master_fd: pty_master_fd
        )
        self
      end

      # Triggers a frame capture with a pre-fetched debug snapshot.
      # The snapshot must be fetched by the caller via DRb before calling this method,
      # because DRb cannot be used inside a Ractor.
      #
      # snapshot: Hash with keys :ts_shell, :cursor ([row, col]), :framework_state (Hash)
      def trigger_capture!(snapshot:, trigger: "on_demand", event_kind: nil)
        return unless @frame_builder
        @frame_builder.send([:capture_with_snapshot, trigger, event_kind, snapshot.freeze])
      end

      # Post-processing: embed all frames that don't yet have a vector entry.
      # Runs synchronously in the calling thread. Use after stop! to batch-embed.
      def embed_pending!
        return if @no_vector || @embedder.nil?

        rows = @storage.db.execute(
          "SELECT f.id, f.content FROM frames f
             LEFT JOIN frame_vec v ON v.frame_id = f.id
            WHERE v.frame_id IS NULL"
        )
        rows.each do |r|
          fid, content = r
          vec = @embedder.embed(content)
          @storage.upsert_frame_vec(fid, vec)
        end
      end

      # Stops the live Ractor pipeline. Safe to call even if pipeline was never started.
      def stop!
        [@pty_reader, @frame_builder, @storage_writer].compact.each do |r|
          r.send([:stop]) rescue nil
        end
        @pty_reader = @frame_builder = @storage_writer = nil
      end
    end
  end
end
