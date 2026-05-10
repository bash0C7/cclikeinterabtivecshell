require "zlib"

module Cclikesh
  module Debug
    module Ractors
      module StorageWriter
        # Spawns a Ractor that receives [:frame, data] messages, writes them to SQLite,
        # and optionally signals a downstream handle about frames that need embedding.
        #
        # Downstream bridge note: The embedder runs as a Thread (not a Ractor) because the
        # informers gem is not Ractor-safe. StorageWriter therefore cannot send directly to
        # a Thread::Queue from inside a Ractor.
        #
        # Pattern used: StorageWriter sends [:frame_to_embed, fid, content] to an optional
        # `embed_bridge` Ractor handle (owned by the orchestrator). The orchestrator's bridge
        # Ractor or the main loop forwards these to the EmbedderThread::Queue.
        # Pass `embed_bridge: nil` to skip embedding entirely (post-processing via embed_pending!).
        def self.spawn(db_path:, embed_bridge: nil)
          Ractor.new(db_path, embed_bridge) do |path, bridge|
            require "sqlite3"
            require "sqlite_vec"
            require "zlib"

            db = SQLite3::Database.new(path, readonly: false)
            db.enable_load_extension(true)
            SqliteVec.load(db)
            db.enable_load_extension(false)

            loop do
              msg = Ractor.receive
              case msg
              in [:frame, data]
                raw_zlib = if data[:raw_bytes] && !data[:raw_bytes].empty?
                  Zlib::Deflate.deflate(data[:raw_bytes])
                end

                db.execute(
                  "INSERT INTO frames(ts, trigger, event_kind, cursor_row, cursor_col,
                                      raw_bytes_zlib, framework_state_json, content, source)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                  [
                    data[:ts], data[:trigger], data[:event_kind],
                    data[:cursor_row], data[:cursor_col],
                    raw_zlib,
                    data[:framework_state_json], data[:content], "framework_state"
                  ]
                )
                fid = db.last_insert_row_id

                bridge&.send([:frame_to_embed, fid, data[:content]])
              in [:eof] | [:stop]
                bridge&.send([:stop])
                db.close rescue nil
                break
              end
            end
          end
        end
      end
    end
  end
end
