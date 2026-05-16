require "extralite"
require "json"
require "time"

module Baslash
  module Debug
    class PtyStorage
      SCHEMA = <<~SQL
        CREATE TABLE IF NOT EXISTS pty_sessions(
          uuid         TEXT PRIMARY KEY,
          started_at   TEXT NOT NULL,
          ended_at     TEXT,
          argv_json    TEXT NOT NULL,
          cols         INTEGER NOT NULL,
          rows         INTEGER NOT NULL,
          env_json     TEXT NOT NULL,
          exit_status  INTEGER,
          spec_path    TEXT,
          timeout_sec  REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS pty_events(
          id            INTEGER PRIMARY KEY,
          session_uuid  TEXT NOT NULL REFERENCES pty_sessions(uuid),
          ts            REAL NOT NULL,
          dir           TEXT NOT NULL CHECK (dir IN ('i','o','x')),
          bytes         BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_pty_events_session_ts
          ON pty_events(session_uuid, ts);
      SQL

      def self.open(path)
        db = Extralite::Database.new(path)
        db.execute("PRAGMA journal_mode = WAL")
        db.execute("PRAGMA foreign_keys = ON")
        db.execute(SCHEMA)
        new(db, path)
      end

      attr_reader :db, :path

      def initialize(db, path)
        @db = db
        @path = path
      end

      def insert_session(uuid:, argv:, cols:, rows:, env:, spec_path:, timeout_sec:)
        @db.execute(
          "INSERT INTO pty_sessions(uuid, started_at, ended_at, argv_json, cols, rows,
                                    env_json, exit_status, spec_path, timeout_sec)
           VALUES (?, ?, NULL, ?, ?, ?, ?, NULL, ?, ?)",
          uuid, Time.now.utc.iso8601(3), argv.to_json, cols, rows,
          env.to_json, spec_path, timeout_sec
        )
      end

      def mark_ended(uuid:, exit_status:)
        @db.execute(
          "UPDATE pty_sessions SET ended_at = ?, exit_status = ? WHERE uuid = ?",
          Time.now.utc.iso8601(3), exit_status, uuid
        )
      end

      def insert_event(session_uuid:, ts:, dir:, bytes:)
        @db.execute(
          "INSERT INTO pty_events(session_uuid, ts, dir, bytes) VALUES (?, ?, ?, ?)",
          session_uuid, ts, dir, bytes.b
        )
      end

      def fetch_session(uuid)
        row = @db.query_single(
          "SELECT uuid, started_at, ended_at, argv_json, cols, rows,
                  env_json, exit_status, spec_path, timeout_sec
           FROM pty_sessions WHERE uuid = ?",
          uuid
        )
        return nil unless row
        {
          uuid:        row[:uuid],
          started_at:  row[:started_at],
          ended_at:    row[:ended_at],
          argv:        JSON.parse(row[:argv_json]),
          cols:        row[:cols],
          rows:        row[:rows],
          env:         JSON.parse(row[:env_json]),
          exit_status: row[:exit_status],
          spec_path:   row[:spec_path],
          timeout_sec: row[:timeout_sec]
        }
      end

      def each_event(session_uuid)
        return enum_for(:each_event, session_uuid) unless block_given?
        @db.query(
          "SELECT ts, dir, bytes FROM pty_events
           WHERE session_uuid = ? ORDER BY ts ASC, id ASC",
          session_uuid
        ).each do |r|
          yield(ts: r[:ts], dir: r[:dir], bytes: r[:bytes])
        end
      end

      def list_sessions
        @db.query(
          "SELECT uuid, started_at, ended_at, argv_json, exit_status, timeout_sec
           FROM pty_sessions ORDER BY started_at DESC"
        ).map do |r|
          {
            uuid:        r[:uuid],
            started_at:  r[:started_at],
            ended_at:    r[:ended_at],
            argv:        JSON.parse(r[:argv_json]),
            exit_status: r[:exit_status],
            timeout_sec: r[:timeout_sec]
          }
        end
      end

      def close
        @db.close rescue nil
      end
    end
  end
end
