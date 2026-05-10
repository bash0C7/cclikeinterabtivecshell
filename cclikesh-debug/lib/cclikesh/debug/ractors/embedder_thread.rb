module Cclikesh
  module Debug
    module Ractors
      # EmbedderThread is NOT a Ractor. It runs as a plain Ruby Thread because the `informers`
      # gem (and its ONNX runtime) accesses shared mutable state that is unsafe in Ractors.
      #
      # Usage (post-processing, driven from Thread::Queue):
      #
      #   queue = Thread::Queue.new
      #   thread = EmbedderThread.spawn(db_path: path, queue: queue, embedder_factory: -> { EmbedderPool.new })
      #
      #   # Enqueue work:
      #   queue.push([:embed, frame_id, content_string])
      #
      #   # Signal stop:
      #   queue.push(:stop)
      #   thread.join
      #
      # The Recorder also supports embed_pending! for a simpler post-session batch approach
      # where no live queue is needed at all.
      module EmbedderThread
        def self.spawn(db_path:, queue:, embedder_factory:)
          Thread.new(db_path, queue, embedder_factory) do |path, q, fac|
            require "sqlite3"
            require "sqlite_vec"

            db = SQLite3::Database.new(path, readonly: false)
            db.enable_load_extension(true)
            SqliteVec.load(db)
            db.enable_load_extension(false)

            embedder = fac.call

            loop do
              msg = q.pop
              case msg
              when :stop
                break
              when Array
                op, fid, content = msg
                next unless op == :embed
                vec = embedder.embed(content)
                blob = vec.pack("f*")
                db.execute(
                  "INSERT OR REPLACE INTO frame_vec(frame_id, embedding) VALUES (?, ?)",
                  [fid, blob]
                )
              end
            end
          ensure
            db&.close rescue nil
          end
        end
      end
    end
  end
end
