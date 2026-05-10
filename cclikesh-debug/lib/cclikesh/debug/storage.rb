require "sqlite3"
require "sqlite_vec"
require "json"
require "time"
require_relative "meta_seeds"

module Cclikesh
  module Debug
    class Storage
      SCHEMA = <<~SQL
        CREATE TABLE session_info(
          uuid TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT,
          shell_argv TEXT NOT NULL, cclikesh_ver TEXT NOT NULL,
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

      def self.create(path, session_uuid:, shell_argv:, cclikesh_ver:, rows:, cols:, embedder:, notes: nil)
        db = SQLite3::Database.new(path)
        db.enable_load_extension(true)
        SqliteVec.load(db)
        db.enable_load_extension(false)
        db.execute("PRAGMA journal_mode = WAL")
        db.execute_batch(SCHEMA)
        db.execute(
          "CREATE VIRTUAL TABLE frame_vec USING vec0(frame_id INTEGER PRIMARY KEY, embedding FLOAT[768])"
        )
        db.execute(
          "INSERT INTO session_info(uuid, started_at, ended_at, shell_argv, cclikesh_ver, rows, cols, embedder, notes)
           VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?)",
          [session_uuid, Time.now.iso8601, shell_argv.to_json, cclikesh_ver, rows, cols, embedder, notes]
        )
        MetaSeeds::ROWS.each do |row|
          db.execute(
            "INSERT INTO _sqlite_mcp_meta(object_type, object_name, description, hints_json, recipe_sql, recipe_label) VALUES (?,?,?,?,?,?)",
            row
          )
        end
        new(db, path)
      end

      def self.open(path, readonly: true)
        db = SQLite3::Database.new(path, readonly: readonly)
        db.enable_load_extension(true)
        SqliteVec.load(db)
        db.enable_load_extension(false)
        new(db, path)
      end

      attr_reader :db, :path

      def initialize(db, path)
        @db = db
        @path = path
      end

      def session_info
        row = @db.execute(
          "SELECT uuid, started_at, ended_at, shell_argv, cclikesh_ver, rows, cols, embedder, notes
           FROM session_info LIMIT 1"
        ).first
        return nil unless row
        {
          uuid: row[0], started_at: row[1], ended_at: row[2],
          shell_argv: JSON.parse(row[3]), cclikesh_ver: row[4],
          rows: row[5], cols: row[6], embedder: row[7], notes: row[8]
        }
      end

      def mark_ended!
        @db.execute("UPDATE session_info SET ended_at = ? WHERE ended_at IS NULL", [Time.now.iso8601])
      end

      def insert_frame(ts:, trigger:, event_kind:, cursor_row:, cursor_col:,
                       raw_bytes_zlib:, framework_state_json:, content:, source:)
        @db.execute(
          "INSERT INTO frames(ts, trigger, event_kind, cursor_row, cursor_col,
                              raw_bytes_zlib, framework_state_json, content, source)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [ts, trigger, event_kind, cursor_row, cursor_col,
           raw_bytes_zlib, framework_state_json, content, source]
        )
        @db.last_insert_row_id
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
        @db.execute(sql, args).map do |r|
          {
            id: r[0], ts: r[1], trigger: r[2], event_kind: r[3],
            cursor_row: r[4], cursor_col: r[5], content: r[6]
          }
        end
      end

      def upsert_frame_vec(frame_id, vec)
        blob = vec.pack("f*")
        @db.execute(
          "INSERT OR REPLACE INTO frame_vec(frame_id, embedding) VALUES (?, ?)",
          [frame_id, blob]
        )
      end

      def close
        @db.close rescue nil
      end
    end
  end
end
