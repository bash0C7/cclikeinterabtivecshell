require "zlib"

module Cclikesh
  module Debug
    module Ractors
      module StorageWriter
        # Spawns a Ractor that opens an Extralite::Database (Ractor-safe SQLite),
        # receives [:frame, data] messages, and writes them with sqlite-vec extension
        # loaded so frame_vec writes from the post-process embed flow remain coherent.
        def self.spawn(db_path:)
          Ractor.new(db_path) do |path|
            require "extralite"
            require "sqlite_vec"
            require "zlib"

            db = Extralite::Database.new(path)
            db.load_extension(SqliteVec.loadable_path)

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
                  data[:ts], data[:trigger], data[:event_kind],
                  data[:cursor_row], data[:cursor_col],
                  raw_zlib,
                  data[:framework_state_json], data[:content], "framework_state"
                )
              in [:eof] | [:stop]
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
