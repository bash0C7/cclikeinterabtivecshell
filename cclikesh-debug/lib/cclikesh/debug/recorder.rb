require "json"
require_relative "storage"
require_relative "content_builder"
require_relative "ractors/pty_reader"
require_relative "ractors/frame_builder"
require_relative "ractors/storage_writer"
require_relative "ractors/embed_storage_writer"

module Cclikesh
  module Debug
    class Recorder
      def initialize(storage:, embedder_factory:, no_vector: false)
        @storage = storage
        @embedder_factory = embedder_factory
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
          if !@no_vector
            embedder = @embedder_factory.call
            vec = embedder.embed(f[:content])
            @storage.upsert_frame_vec(fid, vec)
          end
        end
        @synthetic.clear
      end

      def start_pipeline!(pty_master_fd:)
        @storage_writer = Ractors::StorageWriter.spawn(db_path: @storage.path)
        @frame_builder  = Ractors::FrameBuilder.spawn(downstream: @storage_writer)
        @pty_reader     = Ractors::PtyReader.spawn(downstream: @frame_builder, master_fd: pty_master_fd)
        self
      end

      def trigger_capture!(snapshot:, trigger: "on_demand", event_kind: nil)
        return unless @frame_builder
        frozen = deep_freeze(snapshot)
        @frame_builder.send([:capture_with_snapshot,
                              trigger.to_s.freeze,
                              event_kind&.to_s&.freeze,
                              frozen])
      end

      # Post-process bulk embedding (Case B: subprocess + DRb + EmbedStorageWriter Ractor).
      # The proxy responds to #embed(content) → Array<Float, 768>.
      # Production wires this to a DRbObject pointing at cclikesh-debug-embedder.
      def embed_pending!(proxy:)
        return if @no_vector

        rows = @storage.db.query(
          "SELECT f.id AS id, f.content AS content FROM frames f
             LEFT JOIN frame_vec v ON v.frame_id = f.id
            WHERE v.frame_id IS NULL"
        )
        return if rows.empty?

        writer = Ractors::EmbedStorageWriter.spawn(db_path: @storage.path)
        rows.each do |r|
          vec  = proxy.embed(r[:content])
          blob = vec.pack("f*").freeze
          writer.send([:write, r[:id], blob])
        end
        writer.send([:stop])
        sleep 0.05
      end

      def stop!
        [@pty_reader, @frame_builder, @storage_writer].compact.each do |r|
          (r.send([:stop]) rescue nil)
        end
        sleep 0.05
        @pty_reader = @frame_builder = @storage_writer = nil
      end

      private

      def deep_freeze(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k] = deep_freeze(v) }.freeze
        when Array
          obj.map { |v| deep_freeze(v) }.freeze
        when String
          obj.frozen? ? obj : obj.dup.freeze
        else
          obj
        end
      end
    end
  end
end
