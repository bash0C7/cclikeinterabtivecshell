module Baslash
  module Debug
    module Ractors
      module EmbedStorageWriter
        # Spawns a Ractor that opens an Extralite::Database, loads sqlite-vec,
        # and writes (frame_id, embedding_blob) pairs into frame_vec.
        # Used by the post-process embed flow (subprocess + DRb fetches the vec,
        # then forwards the blob here for storage-side INSERT).
        def self.spawn(db_path:)
          Ractor.new(db_path) do |path|
            require "extralite"
            require "sqlite_vec"

            db = Extralite::Database.new(path)
            db.load_extension(SqliteVec.loadable_path)

            loop do
              msg = Ractor.receive
              case msg
              in [:write, frame_id, blob]
                db.execute(
                  "INSERT OR REPLACE INTO frame_vec(frame_id, embedding) VALUES (?, ?)",
                  frame_id, blob
                )
              in [:stop]
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
