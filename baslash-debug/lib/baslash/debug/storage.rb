require "extralite"
require "sqlite_vec"
require "json"
require "time"
require_relative "meta_seeds"

module Baslash
  module Debug
    class Storage
      SCHEMA = <<~SQL
        CREATE TABLE session_info(
          uuid TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT,
          shell_argv TEXT NOT NULL, baslash_ver TEXT NOT NULL,
          rows INTEGER NOT NULL, cols INTEGER NOT NULL,
          embedder TEXT NOT NULL, notes TEXT
        );
        CREATE TABLE frames(
          id INTEGER PRIMARY KEY, ts REAL NOT NULL, trigger TEXT NOT NULL,
          event_kind TEXT, cursor_row INTEGER NOT NULL, cursor_col INTEGER NOT NULL,
          raw_bytes_zlib BLOB, framework_state_json TEXT NOT NULL,
          content TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'framework_state'
        );
        CREATE INDEX idx_frames_ts ON frames(ts);
        CREATE INDEX idx_frames_event_kind ON frames(event_kind) WHERE event_kind IS NOT NULL;
        CREATE TABLE _sqlite_mcp_meta(
          object_type TEXT, object_name TEXT, description TEXT,
          hints_json TEXT, recipe_sql TEXT, recipe_label TEXT,
          PRIMARY KEY(object_type, object_name)
        );
      SQL

      def self.create(path, session_uuid:, shell_argv:, baslash_ver:, rows:, cols:, embedder:, notes: nil)
        db = Extralite::Database.new(path)
        db.load_extension(SqliteVec.loadable_path)
        db.execute("PRAGMA journal_mode = WAL")
        db.execute(SCHEMA)
        db.execute(
          "CREATE VIRTUAL TABLE frame_vec USING vec0(frame_id INTEGER PRIMARY KEY, embedding FLOAT[768])"
        )
        db.execute(
          "INSERT INTO session_info(uuid, started_at, ended_at, shell_argv, baslash_ver, rows, cols, embedder, notes)
           VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?)",
          session_uuid, Time.now.iso8601, shell_argv.to_json, baslash_ver, rows, cols, embedder, notes
        )
        MetaSeeds::ROWS.each do |row|
          db.execute(
            "INSERT INTO _sqlite_mcp_meta(object_type, object_name, description, hints_json, recipe_sql, recipe_label) VALUES (?,?,?,?,?,?)",
            *row
          )
        end
        new(db, path)
      end

      def self.open(path, readonly: true)
        db = Extralite::Database.new(path, read_only: readonly)
        db.load_extension(SqliteVec.loadable_path)
        new(db, path)
      end

      attr_reader :db, :path

      def initialize(db, path)
        @db = db
        @path = path
      end

      def session_info
        row = @db.query_single(
          "SELECT uuid, started_at, ended_at, shell_argv, baslash_ver, rows, cols, embedder, notes
           FROM session_info LIMIT 1"
        )
        return nil unless row
        {
          uuid: row[:uuid], started_at: row[:started_at], ended_at: row[:ended_at],
          shell_argv: JSON.parse(row[:shell_argv]), baslash_ver: row[:baslash_ver],
          rows: row[:rows], cols: row[:cols], embedder: row[:embedder], notes: row[:notes]
        }
      end

      def mark_ended!
        @db.execute("UPDATE session_info SET ended_at = ? WHERE ended_at IS NULL", Time.now.iso8601)
      end

      def insert_frame(ts:, trigger:, event_kind:, cursor_row:, cursor_col:,
                       raw_bytes_zlib:, framework_state_json:, content:, source:)
        @db.execute(
          "INSERT INTO frames(ts, trigger, event_kind, cursor_row, cursor_col,
                              raw_bytes_zlib, framework_state_json, content, source)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          ts, trigger, event_kind, cursor_row, cursor_col,
          raw_bytes_zlib, framework_state_json, content, source
        )
        @db.last_insert_rowid
      end

      def select_frames(since: nil, until_ts: nil, event_kind: nil, limit: 100)
        where = []
        args = []
        if since;      where << "ts >= ?";        args << since;      end
        if until_ts;   where << "ts <= ?";        args << until_ts;   end
        if event_kind; where << "event_kind = ?"; args << event_kind; end
        sql = "SELECT id, ts, trigger, event_kind, cursor_row, cursor_col, content FROM frames"
        sql += " WHERE #{where.join(' AND ')}" unless where.empty?
        sql += " ORDER BY ts ASC LIMIT ?"
        args << limit
        @db.query(sql, *args).map do |r|
          {
            id: r[:id], ts: r[:ts], trigger: r[:trigger], event_kind: r[:event_kind],
            cursor_row: r[:cursor_row], cursor_col: r[:cursor_col], content: r[:content]
          }
        end
      end

      def upsert_frame_vec(frame_id, vec)
        blob = vec.pack("f*")
        @db.execute(
          "INSERT OR REPLACE INTO frame_vec(frame_id, embedding) VALUES (?, ?)",
          frame_id, blob
        )
      end

      def close
        @db.close rescue nil
      end
    end
  end
end
