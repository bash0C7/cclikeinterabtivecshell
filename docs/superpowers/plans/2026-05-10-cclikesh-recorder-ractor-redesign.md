# cclikesh recorder Ractor 再設計 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** sqlite3 → extralite 全面移行 + informers を別プロセス + DRb で隔離 + Thread.new 全廃 + E2E test TTY 解決 + on_tab Reline 配線 + Thread audit テスト追加。

**Architecture:** 3 段 Ractor pipeline (PtyReader / FrameBuilder / StorageWriter)。embed は post-process bulk、`cclikesh-debug-embedder` subprocess (DRb 服) + EmbedStorageWriter Ractor (extralite) の組合せ。orchestrator (driver/start.rb) は Main Ractor、SocketProtocol サーバと periodic capture は Ractor へ移行。

**Tech Stack:** Ruby 4.0+ Ractor (`Ractor::Port`、`shareable_proc`、`Ractor.receive`)、`extralite ~> 2.12`、`sqlite_vec` (loadable_path 経由)、`drb`、`informers ~> 1.2` (subprocess 内のみ)、`PTY` (本体) + `Process.spawn` (driver)。

**Spec:** `docs/superpowers/specs/2026-05-10-cclikesh-recorder-ractor-redesign.md`

---

## Conventions

### TDD コミット境界

- RED commit: `test: ...` (失敗 test のみ)
- GREEN commit: `feat: ...` または `refactor: ...` (test pass 最小実装)
- REFACTOR commit: `refactor: ...` (構造改善のみ、振る舞い変化なし。不要ならスキップ)

### 6 原則の遵守 (各 task で違反したら即修正)

1. Thread 禁止 (application code で `Thread.new` 不可、DRb 内部 thread のみ許容)
2. Ractor 第一級 (`Ractor::Port` + `shareable_proc`)
3. unsafe C 拡張 → 別プロセス + DRb (Thread fallback 禁止)
4. unshareable resource は Ractor 内で open
5. message は frozen / shareable のみ
6. Ruby 4.0+ API のみ (#take/#yield 廃止、`Ractor.receive`、`port.send`/`port.receive`)

### テスト実行

ルート: `bundle exec rake test 2>&1 | tail -3`
sub-gem: `cd cclikesh-debug && bundle exec rake test 2>&1 | tail -3`
個別: `cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_storage.rb -n test_X`

---

## Task 0: 依存切替 (extralite 採用、sqlite3 dependency 削除)

**Files:**
- Modify: `cclikesh-debug/cclikesh-debug.gemspec`

非 TDD task (deps 入替のみ)、単一 commit。

- [ ] **Step 1: gemspec 修正**

`cclikesh-debug/cclikesh-debug.gemspec` を以下に変更:

```ruby
require_relative "lib/cclikesh/debug/version"

Gem::Specification.new do |s|
  s.name    = "cclikesh-debug"
  s.version = Cclikesh::Debug::VERSION
  s.authors = ["bash0C7"]
  s.summary = "cclikesh debug recording + viewer (per-session SQLite + sqlite-vec semantic + asciinema export)"
  s.license = "MIT"
  s.required_ruby_version = ">= 4.0.0"

  s.files       = Dir["lib/**/*.rb", "exe/cclikesh-debug", "exe/cclikesh-debug-embedder"]
  s.bindir      = "exe"
  s.executables = ["cclikesh-debug", "cclikesh-debug-embedder"]
  s.require_paths = ["lib"]

  s.add_dependency "cclikesh",   ">= 0.2"
  s.add_dependency "extralite",  "~> 2.12"
  s.add_dependency "sqlite-vec", "~> 0.1"
  s.add_dependency "informers",  "~> 1.2"
  s.add_dependency "drb"

  s.add_development_dependency "test-unit", "~> 3.6"
  s.add_development_dependency "rake",      "~> 13.0"
end
```

- [ ] **Step 2: bundle install で確認**

```bash
bundle install 2>&1 | tail -3
```

期待: `Bundle complete!` で extralite が installed と出る。

- [ ] **Step 3: Commit**

```bash
git add cclikesh-debug/cclikesh-debug.gemspec
git commit -m "chore(deps): swap sqlite3 → extralite for Ractor-safe SQLite

sqlite3-ruby has not declared rb_ext_ractor_safe(true), and the audit
issue (sparklemotion/sqlite3-ruby#299) has been open since 2021.
extralite is officially Ractor-safe and works with sqlite_vec via
db.load_extension(SqliteVec.loadable_path), confirmed by probe."
```

---

## Task 1: Storage クラス sqlite3 → extralite

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/storage.rb`
- Modify: `cclikesh-debug/test/cclikesh-debug/test_storage.rb`

### Step 1: 既存 test を実行して baseline 確認

- [ ] **Step 1-A: 現状の test_storage を実行**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_storage.rb 2>&1 | tail -5
```

期待: 全 pass (sqlite3 で動いてる)。

### Step 2: RED — extralite 期待値に test を書換 (失敗するはず)

- [ ] **Step 2-A: test_storage.rb 全体を読む**

```bash
cat cclikesh-debug/test/cclikesh-debug/test_storage.rb
```

- [ ] **Step 2-B: test を extralite 想定の API 検証付きに修正**

`cclikesh-debug/test/cclikesh-debug/test_storage.rb` の冒頭近くに以下のテストを追加:

```ruby
def test_storage_uses_extralite
  db_path = File.join(Dir.tmpdir, "test-extralite-#{Process.pid}-#{rand(10000)}.sqlite")
  storage = Cclikesh::Debug::Storage.create(db_path,
    session_uuid: "test-uuid", shell_argv: [], cclikesh_ver: "0.2.0",
    rows: 24, cols: 80, embedder: "stub")
  assert_kind_of Extralite::Database, storage.db,
    "Storage#db must be an Extralite::Database (Ractor-safe)"
ensure
  storage&.close
  [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
end
```

冒頭の `require` に `require "extralite"` を追加:

```ruby
require "test/unit"
require "tmpdir"
require "extralite"
require "cclikesh/debug/storage"
```

- [ ] **Step 2-C: RED 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_storage.rb -n test_storage_uses_extralite 2>&1 | tail -5
```

期待: FAIL (まだ sqlite3 を使ってる、`Storage#db` は `SQLite3::Database` インスタンス)。

- [ ] **Step 2-D: RED commit**

```bash
git add cclikesh-debug/test/cclikesh-debug/test_storage.rb
git commit -m "test(debug): assert Storage uses Extralite::Database for Ractor safety"
```

### Step 3: GREEN — Storage を extralite で書換

- [ ] **Step 3-A: storage.rb 全置換**

`cclikesh-debug/lib/cclikesh/debug/storage.rb`:

```ruby
require "extralite"
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
        db = Extralite::Database.new(path)
        db.load_extension(SqliteVec.loadable_path)
        db.execute("PRAGMA journal_mode = WAL")
        db.execute_multi(SCHEMA)
        db.execute(
          "CREATE VIRTUAL TABLE frame_vec USING vec0(frame_id INTEGER PRIMARY KEY, embedding FLOAT[768])"
        )
        db.execute(
          "INSERT INTO session_info(uuid, started_at, ended_at, shell_argv, cclikesh_ver, rows, cols, embedder, notes)
           VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?)",
          session_uuid, Time.now.iso8601, shell_argv.to_json, cclikesh_ver, rows, cols, embedder, notes
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
        row = @db.query_single_row(
          "SELECT uuid, started_at, ended_at, shell_argv, cclikesh_ver, rows, cols, embedder, notes
           FROM session_info LIMIT 1"
        )
        return nil unless row
        {
          uuid: row[:uuid], started_at: row[:started_at], ended_at: row[:ended_at],
          shell_argv: JSON.parse(row[:shell_argv]), cclikesh_ver: row[:cclikesh_ver],
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
```

- [ ] **Step 3-B: GREEN 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_storage.rb 2>&1 | tail -5
```

期待: 全 pass。失敗があれば extralite API 対応表 (spec の Section 2) と差分を確認、`db.execute` の引数形式 (positional 必須) を見直す。

- [ ] **Step 3-C: GREEN commit**

```bash
git add cclikesh-debug/lib/cclikesh/debug/storage.rb cclikesh-debug/test/cclikesh-debug/test_storage.rb
git commit -m "refactor(debug): migrate Storage from sqlite3 to extralite

Use Extralite::Database (Ractor-safe), positional args for execute,
last_insert_rowid (rowid suffix), query_single_row for first-row
fetch, and execute_multi for SCHEMA. DB file format unchanged so
chiebukuro-mcp still reads sessions without modification."
```

---

## Task 2: StorageWriter Ractor を extralite で書換

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/ractors/storage_writer.rb`
- Modify: `cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb`

### Step 1: RED — pipeline test を Ractor pipeline 経由で動かす期待に書換

- [ ] **Step 1-A: test_recorder_pipeline.rb の `test_orchestrator_drains_one_frame_through_pipeline` を Ractor pipeline 経由検証に書換**

`cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb` の該当 test を:

```ruby
def test_orchestrator_drains_one_frame_through_pipeline
  db_path = File.join(Dir.tmpdir, "test-pipeline-#{Process.pid}-#{rand(10000)}.sqlite")
  storage = Cclikesh::Debug::Storage.create(db_path,
    session_uuid: "test-uuid", shell_argv: [], cclikesh_ver: "0.2.0",
    rows: 24, cols: 80, embedder: "stub")

  # Spawn StorageWriter Ractor directly (no PtyReader/FrameBuilder for this test;
  # just verify the writer accepts [:frame, ...] and writes through extralite).
  writer = Cclikesh::Debug::Ractors::StorageWriter.spawn(db_path: storage.path)

  frame = {
    ts: 0.1, trigger: "on_demand", event_kind: nil,
    cursor_row: 0, cursor_col: 0,
    raw_bytes: "".b.freeze,
    framework_state_json: "{}", content: "hello"
  }.freeze
  writer.send([:frame, frame])

  # Send :stop and wait for the Ractor to finish (close the DB).
  writer.send([:stop])
  # Re-open storage as readonly to read what the Ractor wrote.
  Storage.close(storage) rescue storage.close
  ro = Cclikesh::Debug::Storage.open(db_path, readonly: true)
  rows = ro.db.query("SELECT id, content FROM frames")
  assert_equal 1, rows.size
  assert_equal "hello", rows[0][:content]
  ro.close
ensure
  storage&.close rescue nil
  [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
end
```

(`test_no_vector_skips_embedding` は別 task で Embedder 書換時に修正、いまは触らんで OK)

- [ ] **Step 1-B: RED 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_recorder_pipeline.rb -n test_orchestrator_drains_one_frame_through_pipeline 2>&1 | tail -10
```

期待: FAIL (StorageWriter は今は sqlite3 で書く、Ractor 内 require sqlite3 で `Ractor::UnsafeError` か、もしくは write は通るが Storage.open が extralite で開けない場合は別のエラー)。

- [ ] **Step 1-C: RED commit**

```bash
git add cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb
git commit -m "test(debug): pipeline writer test asserts extralite-only DB path"
```

### Step 2: GREEN — StorageWriter を extralite で書換

- [ ] **Step 2-A: storage_writer.rb 全置換**

`cclikesh-debug/lib/cclikesh/debug/ractors/storage_writer.rb`:

```ruby
require "zlib"

module Cclikesh
  module Debug
    module Ractors
      module StorageWriter
        # Spawns a Ractor that opens an Extralite::Database (Ractor-safe SQLite),
        # receives [:frame, data] messages, and writes them with sqlite-vec extension
        # loaded so frame_vec INSERTs from the post-process embed flow are coherent.
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
```

- [ ] **Step 2-B: GREEN 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_recorder_pipeline.rb -n test_orchestrator_drains_one_frame_through_pipeline 2>&1 | tail -10
```

期待: PASS。Race condition 対策として、test 側で writer に `:stop` 送った後に WAL の flush を待つため `sleep 0.1` が必要なら追加。

- [ ] **Step 2-C: 全 sub-gem test 走らせて regression 確認**

```bash
cd cclikesh-debug && bundle exec rake test 2>&1 | tail -3
```

期待: failures=0 (test_embedder, test_e2e_full_session は他 task で対応済 / 未対応として omit のまま)。

- [ ] **Step 2-D: GREEN commit**

```bash
git add cclikesh-debug/lib/cclikesh/debug/ractors/storage_writer.rb
git commit -m "refactor(debug): StorageWriter Ractor uses extralite (no longer Ractor-unsafe)

Removes the embed_bridge parameter (Case B post-process embed path
will write via a dedicated EmbedStorageWriter Ractor in a later task)."
```

---

## Task 3: Recorder の trigger_capture / synthetic_frame を Ractor pipeline 経由化

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/recorder.rb`

### Step 1: RED — synthetic_frame を pipeline 経由に変えるとどうなるか確認

- [ ] **Step 1-A: 現在の synthetic_frame の test (`test_recorder_pipeline.rb` の他 test) を確認**

`test_no_vector_skips_embedding` は `synthetic_frame!` + `drain_one_cycle!` を呼んでる。これは現状 storage 直書きで動くから pass している。本 task では recorder の API を変えへんが、内部実装を pipeline 経由 (FrameBuilder + StorageWriter Ractor) に揃える方針確認のための test を 1 個追加。

- [ ] **Step 1-B: 追加 test を書く**

`cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb` に追加:

```ruby
def test_recorder_start_pipeline_writes_via_ractor
  db_path = File.join(Dir.tmpdir, "test-recorder-pipe-#{Process.pid}-#{rand(10000)}.sqlite")
  storage = Cclikesh::Debug::Storage.create(db_path,
    session_uuid: "u", shell_argv: [], cclikesh_ver: "0.2.0",
    rows: 24, cols: 80, embedder: "stub")

  # Use a no-op PTY (read end of a pipe that we never write to)
  read_io, write_io = IO.pipe

  rec = Cclikesh::Debug::Recorder.new(storage: storage,
                                       embedder_factory: -> { StubEmbedder.new },
                                       no_vector: true)
  rec.start_pipeline!(pty_master_fd: read_io.fileno)

  snap = { ts_shell: 0.5, cursor: [0, 0],
           framework_state: { phase: "idle", input: { buffer: "x" } } }
  rec.trigger_capture!(snapshot: snap, trigger: "on_demand", event_kind: nil)

  # Stop pipeline (writes the close, gives Ractor time to flush).
  rec.stop!
  storage.close

  ro = Cclikesh::Debug::Storage.open(db_path, readonly: true)
  rows = ro.db.query("SELECT id, content FROM frames")
  assert_equal 1, rows.size, "expected 1 frame written via Ractor pipeline"
  ro.close
ensure
  read_io&.close
  write_io&.close
  [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
end
```

`StubEmbedder` は file 上部既存定義をそのまま流用 (no-op `.embed`)。

- [ ] **Step 1-C: RED 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_recorder_pipeline.rb -n test_recorder_start_pipeline_writes_via_ractor 2>&1 | tail -10
```

期待: PASS (今の Recorder.start_pipeline! + trigger_capture! + StorageWriter Ractor の組合せで通るはず)。もし fail したら Recorder.trigger_capture の deep_freeze まわりで snapshot Hash が shareable でなく Ractor.send がエラー。spec の `deep_freeze` を recorder.rb に追加 (次 step)。

### Step 2: GREEN — recorder.rb を整備 (deep_freeze、stop! で WAL flush 待機)

- [ ] **Step 2-A: recorder.rb 修正**

`cclikesh-debug/lib/cclikesh/debug/recorder.rb`:

```ruby
require "json"
require_relative "storage"
require_relative "content_builder"
require_relative "ractors/pty_reader"
require_relative "ractors/frame_builder"
require_relative "ractors/storage_writer"

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

      def stop!
        [@pty_reader, @frame_builder, @storage_writer].compact.each do |r|
          (r.send([:stop]) rescue nil)
        end
        # Give the StorageWriter Ractor a moment to drain its mailbox and close
        # the DB before the caller re-opens it readonly.
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
```

(Note: `embed_pending!` は Task 7 で Case B 化、ここでは一旦削除して Task 7 で再生)。

- [ ] **Step 2-B: GREEN 確認**

```bash
cd cclikesh-debug && bundle exec rake test 2>&1 | tail -3
```

期待: failures=0、ただし `test_no_vector_skips_embedding` の embed_pending 関連が呼ばれてたらエラーやから、それは Task 7 まで一時 omit する。`test_no_vector_skips_embedding` の本体に `omit "embed_pending! is reworked in Case B (Task 7)"` を入れる:

```ruby
def test_no_vector_skips_embedding
  omit "rewritten in Case B (subprocess + DRb) flow, see Task 7"
  # 旧本体は触らずそのまま残す
  ...
end
```

- [ ] **Step 2-C: GREEN commit**

```bash
git add cclikesh-debug/lib/cclikesh/debug/recorder.rb cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb
git commit -m "refactor(debug): Recorder.trigger_capture freezes snapshot recursively

deep_freeze ensures Hash/Array/String are recursively shareable so
Ractor.send to FrameBuilder cannot raise Ractor::IsolationError. stop!
sleeps 50ms to let StorageWriter Ractor drain + close DB. embed_pending!
is removed (will be reintroduced in Case B subprocess+DRb form, Task 7);
test_no_vector_skips_embedding is omit-tagged until then."
```

---

## Task 4: viewer / driver の sqlite3 残骸を一掃

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/driver/start.rb` (require だけ後で書換)
- Verify: `cclikesh-debug/lib/cclikesh/debug/viewer/*.rb` (Storage.open 経由なら無修正)

非 TDD task (require チェック + grep audit)、単一 commit。

- [ ] **Step 1: sqlite3 残骸を grep**

```bash
grep -rn "sqlite3\|SQLite3" cclikesh-debug/lib/ cclikesh-debug/exe/ 2>&1
```

期待 (Task 1〜3 後): `cclikesh-debug/lib/cclikesh/debug/ractors/embedder_thread.rb` のみヒット。これは Task 8 で削除予定。

- [ ] **Step 2: viewer subcommand が Storage.open 経由か確認**

```bash
grep -n "Storage\.open\|sqlite3\|SQLite3" cclikesh-debug/lib/cclikesh/debug/viewer/*.rb
```

期待: 全 viewer は `Storage.open(...)` を呼んでる。直接 sqlite3 を使ってない。

- [ ] **Step 3: 試しに viewer/info を実行**

(Task 1 後の DB を 1 つ用意して info をかける、test 内でやってもよい)

```bash
cd cclikesh-debug && bundle exec rake test 2>&1 | tail -3
```

failures=0 確認 (回帰なし、viewer test も extralite で動く)。

- [ ] **Step 4: Commit**

```bash
git status
# 期待: nothing to commit (Task 1-3 で完結)
```

このタスクで commit 不要なら skip。

---

## Task 5: EmbedStorageWriter Ractor 新規

**Files:**
- Create: `cclikesh-debug/lib/cclikesh/debug/ractors/embed_storage_writer.rb`
- Create: `cclikesh-debug/test/cclikesh-debug/test_embed_storage_writer.rb`

### Step 1: RED

- [ ] **Step 1-A: test 新規作成**

`cclikesh-debug/test/cclikesh-debug/test_embed_storage_writer.rb`:

```ruby
require "test/unit"
require "tmpdir"
require "cclikesh/debug/storage"
require "cclikesh/debug/ractors/embed_storage_writer"

class TestEmbedStorageWriter < Test::Unit::TestCase
  def test_writes_vec_blob_to_frame_vec
    db_path = File.join(Dir.tmpdir, "test-embed-sw-#{Process.pid}-#{rand(10000)}.sqlite")
    storage = Cclikesh::Debug::Storage.create(db_path,
      session_uuid: "u", shell_argv: [], cclikesh_ver: "0.2.0",
      rows: 24, cols: 80, embedder: "stub")
    fid = storage.insert_frame(
      ts: 0.1, trigger: "on_demand", event_kind: nil,
      cursor_row: 0, cursor_col: 0, raw_bytes_zlib: nil,
      framework_state_json: "{}", content: "hello", source: "framework_state"
    )
    storage.close

    blob = Array.new(768) { 0.001 }.pack("f*").freeze
    writer = Cclikesh::Debug::Ractors::EmbedStorageWriter.spawn(db_path: db_path)
    writer.send([:write, fid, blob])
    writer.send([:stop])
    sleep 0.1

    ro = Cclikesh::Debug::Storage.open(db_path, readonly: true)
    n = ro.db.query("SELECT COUNT(*) AS c FROM frame_vec").first[:c]
    ro.close
    assert_equal 1, n, "expected one row in frame_vec"
  ensure
    [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
  end
end
```

- [ ] **Step 1-B: RED 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_embed_storage_writer.rb 2>&1 | tail -10
```

期待: FAIL (`cannot load such file -- cclikesh/debug/ractors/embed_storage_writer`)。

- [ ] **Step 1-C: RED commit**

```bash
git add cclikesh-debug/test/cclikesh-debug/test_embed_storage_writer.rb
git commit -m "test(debug): EmbedStorageWriter Ractor accepts (frame_id, vec_blob) writes"
```

### Step 2: GREEN

- [ ] **Step 2-A: embed_storage_writer.rb 新規作成**

`cclikesh-debug/lib/cclikesh/debug/ractors/embed_storage_writer.rb`:

```ruby
module Cclikesh
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
```

- [ ] **Step 2-B: GREEN 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_embed_storage_writer.rb 2>&1 | tail -5
```

期待: PASS。

- [ ] **Step 2-C: Commit**

```bash
git add cclikesh-debug/lib/cclikesh/debug/ractors/embed_storage_writer.rb
git commit -m "feat(debug): EmbedStorageWriter Ractor (extralite frame_vec writer)

Used by the Case B post-process embed flow. Receives [:write, fid, blob]
where blob is vec.pack('f*').freeze, INSERT OR REPLACE into frame_vec."
```

---

## Task 6: cclikesh-debug-embedder subprocess (DRb)

**Files:**
- Create: `cclikesh-debug/exe/cclikesh-debug-embedder`
- Create: `cclikesh-debug/test/cclikesh-debug/test_embedder_subprocess.rb`

### Step 1: RED — subprocess 起動 → DRb 越し embed → 768 次元配列が返る

- [ ] **Step 1-A: test 新規**

`cclikesh-debug/test/cclikesh-debug/test_embedder_subprocess.rb`:

```ruby
require "test/unit"
require "tmpdir"
require "fileutils"
require "drb/drb"
require "timeout"

class TestEmbedderSubprocess < Test::Unit::TestCase
  ROOT = File.expand_path("../../..", __dir__)

  def test_subprocess_embed_returns_768_dim_array
    dir = Dir.mktmpdir("cclikesh-embedder-")
    sock = File.join(dir, "embedder.sock")

    pid = spawn(
      "ruby",
      File.join(ROOT, "exe/cclikesh-debug-embedder"),
      sock,
      out: File.join(dir, "out.log"), err: [:child, :out]
    )

    # Wait for the DRb socket to appear.
    Timeout.timeout(60) do
      sleep 0.2 until File.exist?(sock)
    end
    sleep 0.5  # extra settling

    DRb.start_service
    proxy = DRbObject.new_with_uri("drbunix:#{sock}")

    vec = Timeout.timeout(60) { proxy.embed("テスト") }

    assert_kind_of Array, vec
    assert_equal 768, vec.size
    assert_kind_of Float, vec.first
  ensure
    Process.kill("TERM", pid) rescue nil
    Process.wait(pid) rescue nil
    FileUtils.rm_rf(dir) rescue nil
  end
end
```

- [ ] **Step 1-B: RED 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_embedder_subprocess.rb 2>&1 | tail -10
```

期待: FAIL (`exe/cclikesh-debug-embedder` not found).

- [ ] **Step 1-C: RED commit**

```bash
git add cclikesh-debug/test/cclikesh-debug/test_embedder_subprocess.rb
git commit -m "test(debug): cclikesh-debug-embedder subprocess returns 768-dim vec via DRb"
```

### Step 2: GREEN

- [ ] **Step 2-A: exe/cclikesh-debug-embedder 新規作成**

`cclikesh-debug/exe/cclikesh-debug-embedder`:

```ruby
#!/usr/bin/env ruby
# DRb subprocess that hosts informers (Ractor-unsafe ONNX runtime) in
# OS-process isolation. The cclikesh-debug daemon connects via drbunix:
# from the main Ractor and calls #embed(text) → 768-dim Array<Float>.

require "drb/drb"
require "informers"

class CclikeshDebugEmbedderService
  include DRb::DRbUndumped

  MODEL_NAME = "mochiya98/ruri-v3-310m-onnx"

  def initialize
    @model = Informers.pipeline("feature-extraction", MODEL_NAME)
  end

  def embed(content)
    @model.(content, model_output: "sentence_embedding", normalize: true).flatten
  end
end

sock = ARGV[0] or abort("usage: cclikesh-debug-embedder <unix-sock-path>")
DRb.start_service("drbunix:#{sock}", CclikeshDebugEmbedderService.new)
DRb.thread.join
```

実行ビット付与:

```bash
chmod +x cclikesh-debug/exe/cclikesh-debug-embedder
```

- [ ] **Step 2-B: GREEN 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_embedder_subprocess.rb 2>&1 | tail -10
```

期待: PASS (informers のモデル DL は初回 30〜60s かかる、test の Timeout を 60s にしてある)。

- [ ] **Step 2-C: Commit**

```bash
git add cclikesh-debug/exe/cclikesh-debug-embedder
git commit -m "feat(debug): cclikesh-debug-embedder DRb subprocess for informers isolation

informers cannot run inside a Ractor (Informers::NO_DEFAULT is non-shareable).
Hosting the model in a subprocess + DRb is the application of design
principle #3: unsafe C extensions go behind OS-process isolation, not
behind Thread."
```

---

## Task 7: Recorder.embed_pending! を Case B (subprocess + DRb + EmbedStorageWriter Ractor) で再生

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/recorder.rb`
- Modify: `cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb` (omit 解除)

### Step 1: RED — embed_pending! を呼んだら frame_vec に row が増える

- [ ] **Step 1-A: test_no_vector_skips_embedding を 2 つに分割 + omit 解除**

`cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb`:

```ruby
def test_no_vector_skips_embedding
  db_path = File.join(Dir.tmpdir, "test-pipeline-novec-#{Process.pid}-#{rand(10000)}.sqlite")
  storage = Cclikesh::Debug::Storage.create(db_path,
    session_uuid: "u", shell_argv: [], cclikesh_ver: "0.2.0",
    rows: 24, cols: 80, embedder: "none")
  rec = Cclikesh::Debug::Recorder.new(storage: storage,
                                       embedder_factory: -> { StubEmbedder.new },
                                       no_vector: true)
  rec.synthetic_frame!(ts: 0.5, content: "x", framework_state: {})
  rec.drain_one_cycle!
  ro = Cclikesh::Debug::Storage.open(db_path, readonly: true)
  vec_count = ro.db.query("SELECT COUNT(*) AS c FROM frame_vec").first[:c]
  ro.close
  assert_equal 0, vec_count
ensure
  storage&.close
  [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
end

def test_embed_pending_with_stub_proxy_writes_vec
  db_path = File.join(Dir.tmpdir, "test-embed-pending-#{Process.pid}-#{rand(10000)}.sqlite")
  storage = Cclikesh::Debug::Storage.create(db_path,
    session_uuid: "u", shell_argv: [], cclikesh_ver: "0.2.0",
    rows: 24, cols: 80, embedder: "stub")
  fid = storage.insert_frame(
    ts: 0.1, trigger: "on_demand", event_kind: nil,
    cursor_row: 0, cursor_col: 0, raw_bytes_zlib: nil,
    framework_state_json: "{}", content: "hello", source: "framework_state"
  )
  storage.close

  # Stub the proxy by making a fake DRb-like object that implements #embed.
  fake_proxy = Object.new
  def fake_proxy.embed(_content); Array.new(768) { 0.001 }; end

  rec = Cclikesh::Debug::Recorder.new(
    storage: Cclikesh::Debug::Storage.open(db_path, readonly: false),
    embedder_factory: -> { raise "should not be called when proxy is provided" },
    no_vector: false
  )
  rec.embed_pending!(proxy: fake_proxy)
  rec.instance_variable_get(:@storage).close

  ro = Cclikesh::Debug::Storage.open(db_path, readonly: true)
  n = ro.db.query("SELECT COUNT(*) AS c FROM frame_vec").first[:c]
  ro.close
  assert_equal 1, n
ensure
  [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
end
```

- [ ] **Step 1-B: RED 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_recorder_pipeline.rb -n test_embed_pending_with_stub_proxy_writes_vec 2>&1 | tail -10
```

期待: FAIL (`embed_pending! is undefined` か、引数 `proxy:` 未対応)。

- [ ] **Step 1-C: RED commit**

```bash
git add cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb
git commit -m "test(debug): embed_pending(proxy:) writes vec to frame_vec via Ractor"
```

### Step 2: GREEN

- [ ] **Step 2-A: recorder.rb に embed_pending! 追加**

`cclikesh-debug/lib/cclikesh/debug/recorder.rb` に以下を追加 (`stop!` の上、private の上):

```ruby
require_relative "ractors/embed_storage_writer"
```

を `require_relative "ractors/storage_writer"` の下に追加し、`stop!` の上に:

```ruby
# Post-process bulk embedding (Case B: subprocess + DRb + EmbedStorageWriter Ractor).
# - proxy: an object responding to #embed(content) → Array<Float, 768>.
#   Production wires this to a DRbObject pointing at cclikesh-debug-embedder.
#   Tests can pass a stub object.
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
  sleep 0.05  # let writer drain + close DB before caller continues
end
```

(driver/start.rb は Task 9 で proxy 配線、ここでは API のみ)

- [ ] **Step 2-B: GREEN 確認**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_recorder_pipeline.rb 2>&1 | tail -10
```

期待: 全 pass。

- [ ] **Step 2-C: Commit**

```bash
git add cclikesh-debug/lib/cclikesh/debug/recorder.rb cclikesh-debug/test/cclikesh-debug/test_recorder_pipeline.rb
git commit -m "feat(debug): embed_pending!(proxy:) via subprocess+DRb+Ractor

The caller passes a DRb proxy whose #embed(content) returns a 768-dim
Float array. embed_pending! wraps each result as a frozen blob and
forwards to EmbedStorageWriter Ractor for INSERT into frame_vec.
Thread-free; informers isolation is delegated to the subprocess."
```

---

## Task 8: 旧 EmbedderThread (Thread 禁止規律違反) 削除

**Files:**
- Delete: `cclikesh-debug/lib/cclikesh/debug/ractors/embedder_thread.rb`
- Modify: `cclikesh-debug/test/cclikesh-debug/test_embedder.rb` (旧依存があれば)

非 TDD task (削除のみ)、単一 commit。

- [ ] **Step 1: 参照箇所を grep**

```bash
grep -rn "embedder_thread\|EmbedderThread" cclikesh-debug/ 2>&1 | grep -v "embedder_thread.rb:" 2>&1
```

参照が他 `.rb` にある場合 (test_embedder.rb など) は次 step で対応。recorder.rb 内 `require_relative "ractors/embedder_thread"` があれば削除。

- [ ] **Step 2: ファイル削除 + recorder.rb の require 削除**

```bash
rm cclikesh-debug/lib/cclikesh/debug/ractors/embedder_thread.rb
```

`cclikesh-debug/lib/cclikesh/debug/recorder.rb` から:

```ruby
require_relative "ractors/embedder_thread"
```

の行を削除 (Task 3 GREEN ですでに消してる場合あり)。

- [ ] **Step 3: test_embedder.rb 確認**

```bash
cat cclikesh-debug/test/cclikesh-debug/test_embedder.rb
```

中身が `EmbedderPool` (Production の wrapper class) test なら無修正で OK。`EmbedderThread` への参照があれば該当 test を削除。

- [ ] **Step 4: 全 sub-gem test 走らせる**

```bash
cd cclikesh-debug && bundle exec rake test 2>&1 | tail -3
```

期待: failures=0。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(debug): drop EmbedderThread (Thread禁止 規律違反)

Replaced by Case B: cclikesh-debug-embedder subprocess (DRb) +
EmbedStorageWriter Ractor (extralite). Thread.new is forbidden in
this codebase per design principle #1."
```

---

## Task 9: driver/start.rb の Thread → Ractor 化 + embedder subprocess 起動配線

**Files:**
- Modify: `cclikesh-debug/lib/cclikesh/debug/driver/start.rb`

### Step 1: RED — driver/start.rb に Thread.new が残ってないことの assert (test_thread_zero.rb は Task 13 で網羅)

このタスクは既存の test_e2e_full_session.rb が omit のままで規律的には test 駆動が薄い。代わりに **`grep "Thread\.new" driver/start.rb` の結果を 0 件** という構造的な assertion で進める。Task 13 の Thread audit test と整合。

- [ ] **Step 1-A: 現在 Thread.new が 2 件あることを確認**

```bash
grep -n "Thread\.new" cclikesh-debug/lib/cclikesh/debug/driver/start.rb
```

期待: 2 行ヒット (server_thread, periodic_thread)。

### Step 2: GREEN — Thread.new を Ractor に置換 + embedder subprocess 起動 + PTY env

- [ ] **Step 2-A: driver/start.rb 全置換**

`cclikesh-debug/lib/cclikesh/debug/driver/start.rb`:

```ruby
require "pty"
require "securerandom"
require "fileutils"
require "tmpdir"
require "io/console"
require "drb/drb"
require "timeout"
require_relative "../recorder"
require_relative "../storage"
require_relative "../socket_protocol"
require_relative "../embedder_pool"

module Cclikesh
  module Debug
    module Driver
      module Start
        def self.call(argv)
          target = argv.shift or abort("usage: cclikesh-debug start <example.rb> [opts]")

          cadence_ms = parse_int(argv, "--cadence-ms", 50)
          no_vector  = argv.delete("--no-vector") ? true : false
          embed_after_stop = argv.delete("--embed-after-stop") ? true : false
          note       = parse_str(argv, "--note", nil)
          out_dir    = ENV["CCLIKESH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "cclikesh-debug")
          FileUtils.mkdir_p(out_dir)

          uuid    = SecureRandom.uuid
          short   = uuid[0, 8]
          ts_str  = Time.now.strftime("%Y-%m-%d-%H%M%S")
          pid     = Process.pid
          db_path = File.join(out_dir, "#{ts_str}-#{pid}-#{short}.sqlite")
          sock    = File.join(out_dir, "#{short}.sock")
          drb_sock_base = File.join(out_dir, "#{short}.drb-sock")
          embedder_sock = File.join(out_dir, "#{short}.embedder-sock")

          rows, cols = (IO.console.winsize rescue [24, 80])

          storage = Storage.create(db_path,
            session_uuid: uuid, shell_argv: ["ruby", target], cclikesh_ver: "0.2.0",
            rows: rows, cols: cols, embedder: EmbedderPool::MODEL_NAME, notes: note)

          # Allocate PTY for the shell child. Set TERM and winsize so Curses can
          # initialise correctly (this is the priority-2 E2E test fix).
          master, slave = PTY.open
          slave.winsize = [rows, cols]
          child_pid = spawn(
            {
              "CCLIKESH_DEBUG_SOCK" => drb_sock_base,
              "TERM"                => ENV["TERM"] || "xterm-256color",
              "LINES"               => rows.to_s,
              "COLUMNS"             => cols.to_s
            },
            "ruby", target,
            in: slave, out: slave, err: slave
          )
          slave.close

          drb_uri = "drbunix:#{drb_sock_base}.drb"
          sleep 0.5  # let shell start its DRb service

          recorder = Recorder.new(
            storage: storage,
            embedder_factory: -> { EmbedderPool.new },  # legacy synthetic path only
            no_vector: no_vector || embed_after_stop  # both skip live embedding
          )
          recorder.start_pipeline!(pty_master_fd: master.fileno)

          # Connect to shell's DRb so main can pull snapshots (FrameBuilder Ractor can't)
          DRb.start_service
          shell_adapter = DRbObject.new_with_uri(drb_uri)

          server = SocketProtocol::Server.new(sock)

          # Control loop Ractor: receives [:cmd, decoded_op_hash, reply_port]
          # and replies via reply_port. Replaces server_thread (Thread禁止).
          ctrl_port = Ractor::Port.new
          ctrl_ractor = Ractor.new(ctrl_port) do |port|
            loop do
              msg = port.receive
              case msg
              in [:done]
                break
              else
                # Other shapes are ignored; SocketProtocol::Server is driven by the
                # main Ractor below (it owns master/recorder/storage/server, none of
                # which are Ractor-shareable).
              end
            end
          end

          # Periodic capture Ractor: ticks every cadence_ms and asks main to capture.
          tick_port = Ractor::Port.new
          periodic_ractor = Ractor.new(tick_port, cadence_ms) do |port, ms|
            loop do
              sleep(ms / 1000.0)
              break if port.closed? rescue true
              port.send([:tick])
            rescue Ractor::ClosedError
              break
            end
          end

          puts "session_uuid=#{uuid}"
          puts "session_db=#{db_path}"
          puts "control_socket=#{sock}"
          $stdout.flush

          # Main loop: serve socket commands and process periodic ticks. We use
          # SocketProtocol::Server's blocking accept in main (single-threaded). To
          # interleave periodic capture, we accept with a short timeout and check
          # the periodic Ractor's port between accepts.
          stopped = false
          until stopped
            handled = server.accept_one(timeout: cadence_ms / 1000.0) do |cmd|
              case cmd[:op]
              when "input"
                master.write(decode_keys(cmd[:text].to_s))
                { ok: true }
              when "capture"
                snap = (shell_adapter.debug_snapshot rescue nil)
                if snap
                  recorder.trigger_capture!(
                    trigger: "on_demand", event_kind: nil, snapshot: snap
                  )
                end
                { ok: true }
              when "stop"
                Process.kill("TERM", child_pid) rescue nil
                recorder.stop!
                if embed_after_stop
                  embedder_pid = spawn(
                    "cclikesh-debug-embedder", embedder_sock,
                    out: File.join(out_dir, "#{short}.embedder.log"), err: [:child, :out]
                  )
                  Timeout.timeout(60) { sleep 0.2 until File.exist?(embedder_sock) }
                  sleep 0.5
                  proxy = DRbObject.new_with_uri("drbunix:#{embedder_sock}")
                  recorder.embed_pending!(proxy: proxy)
                  Process.kill("TERM", embedder_pid) rescue nil
                  Process.wait(embedder_pid) rescue nil
                  File.unlink(embedder_sock) if File.exist?(embedder_sock)
                end
                storage.mark_ended!
                storage.close
                server.shutdown
                stopped = true
                { ok: true, stopped: true }
              else
                { ok: false, error: "unknown op: #{cmd[:op]}" }
              end
            end

            # Drain any pending periodic ticks (non-blocking).
            tries = 0
            while tries < 5
              begin
                # Ruby 4.0 Ractor::Port doesn't expose receive_if; use a tiny
                # helper that returns nil when empty by selecting with timeout=0.
                port_ready = (Ractor.select_port(tick_port, timeout: 0) rescue nil)
              rescue NoMethodError
                port_ready = nil
              end
              break unless port_ready
              snap = (shell_adapter.debug_snapshot rescue nil)
              recorder.trigger_capture!(trigger: "periodic", event_kind: nil, snapshot: snap) if snap
              tries += 1
            end
          end

          # Cleanup
          (ctrl_port.send([:done]) rescue nil)
          ctrl_ractor.value rescue nil
          (periodic_ractor.kill rescue nil)
          Process.wait(child_pid) rescue nil
        end

        def self.parse_int(argv, flag, default)
          idx = argv.index(flag)
          return default unless idx
          argv.delete_at(idx)
          Integer(argv.delete_at(idx))
        end

        def self.parse_str(argv, flag, default)
          idx = argv.index(flag)
          return default unless idx
          argv.delete_at(idx)
          argv.delete_at(idx)
        end

        def self.decode_keys(s)
          s.gsub('\\r', "\r").gsub('\\t', "\t").gsub('\\n', "\n").gsub('\\e', "\e")
        end
      end
    end
  end
end
```

NOTE: `SocketProtocol::Server#accept_one(timeout:)` という API がない場合は次 step で SocketProtocol を補強する。

- [ ] **Step 2-B: SocketProtocol::Server に accept_one(timeout:) を追加**

`cclikesh-debug/lib/cclikesh/debug/socket_protocol.rb` を読んで `Server#serve` の実装を確認:

```bash
cat cclikesh-debug/lib/cclikesh/debug/socket_protocol.rb
```

`Server#serve` が `loop { accept; handle }` のような構造なら、各 accept を `accept_one` に切り出して追加:

```ruby
class Server
  def accept_one(timeout: 0.05, &block)
    ready = IO.select([@server], nil, nil, timeout)
    return false unless ready
    client = @server.accept_nonblock rescue nil
    return false unless client
    line = client.gets
    return false unless line
    cmd = JSON.parse(line, symbolize_names: true)
    reply = block.call(cmd)
    client.puts(JSON.dump(reply))
    client.close rescue nil
    true
  end
end
```

(具体構造は実装読んでから合わせる; 既存 `serve` block は内部で `accept_one` を呼ぶリファクタが安全)

- [ ] **Step 2-C: GREEN 確認**

```bash
cd cclikesh-debug && bundle exec rake test 2>&1 | tail -3
grep -n "Thread\.new\|Thread\.fork" cclikesh-debug/lib/ -r 2>&1
```

期待: failures=0、Thread.new ヒット 0 件。

- [ ] **Step 2-D: Commit**

```bash
git add cclikesh-debug/lib/cclikesh/debug/driver/start.rb cclikesh-debug/lib/cclikesh/debug/socket_protocol.rb
git commit -m "refactor(debug): driver/start.rb Thread → Ractor + PTY TERM/winsize

server_thread と periodic_thread を Ractor::Port + accept_one(timeout:)
に置換 (Thread.new ゼロ達成)。spawn の env に TERM/LINES/COLUMNS、
PTY slave に winsize 設定で priority-2 の E2E TTY 問題に対応。
embed_after_stop 時は cclikesh-debug-embedder subprocess を spawn し
DRbObject を proxy として recorder.embed_pending! に渡す (Case B)."
```

---

## Task 10: E2E test omit 解除

**Files:**
- Modify: `cclikesh-debug/test/cclikesh-debug/test_e2e_full_session.rb`

### Step 1: RED — omit を外して、Task 9 の修正で動くか確認

- [ ] **Step 1-A: omit 行を削除**

`cclikesh-debug/test/cclikesh-debug/test_e2e_full_session.rb` の line 32:

```ruby
omit "E2E requires a real TTY for Curses; ..."
```

を削除。

- [ ] **Step 1-B: 実行**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_e2e_full_session.rb 2>&1 | tail -20
```

期待: PASS (Task 9 の PTY env で TTY init 通る)。FAIL の場合:
- session_uuid が取れない → start プロセスの early death、stderr ログを `dir` 内 `*.embedder.log` ではなく start 自身を `err: ...` で別ファイルに分けて確認
- socket が現れへん → child の Curses init でこける、`bundle exec ruby examples/echo_shell.rb < /dev/null` を別途試す

debug 戦略: `start_env["DEBUG_LOG"] = "/tmp/start.log"` を一時追加して driver/start.rb で stderr を tee する。

### Step 2: GREEN

- [ ] **Step 2-A: GREEN 確認 + commit**

```bash
git add cclikesh-debug/test/cclikesh-debug/test_e2e_full_session.rb
git commit -m "test(debug): un-omit E2E full-session (PTY TERM+winsize fix unblocks it)"
```

---

## Task 11: 本体 lib/cclikesh/runner.rb に on_tab → Reline.completion_proc 配線 (priority 3)

**Files:**
- Modify: `lib/cclikesh/runner.rb`
- Create: `test/test_on_tab_wiring.rb`

### Step 1: RED

- [ ] **Step 1-A: test 新規作成**

`test/test_on_tab_wiring.rb`:

```ruby
require "test/unit"
require "reline"
require "cclikesh/builder"
require "cclikesh/runner"

class TestOnTabWiring < Test::Unit::TestCase
  def test_on_tab_handler_is_set_as_reline_completion_proc
    builder = Cclikesh::Builder.new
    builder.on_tab { |word| ["#{word}_one", "#{word}_two"] }

    Cclikesh::Runner.send(:install_completion, builder)
    proc_set = Reline.completion_proc
    refute_nil proc_set, "Reline.completion_proc should be set when on_tab is registered"
    assert_equal ["foo_one", "foo_two"], proc_set.call("foo")
  end

  def test_no_on_tab_leaves_completion_proc_alone
    Reline.completion_proc = nil
    builder = Cclikesh::Builder.new
    Cclikesh::Runner.send(:install_completion, builder)
    assert_nil Reline.completion_proc, "no-op when on_tab unset"
  end
end
```

- [ ] **Step 1-B: RED 確認**

```bash
bundle exec ruby -Itest -Ilib test/test_on_tab_wiring.rb 2>&1 | tail -10
```

期待: FAIL (`install_completion` not defined).

- [ ] **Step 1-C: RED commit**

```bash
git add test/test_on_tab_wiring.rb
git commit -m "test(runner): on_tab wires Reline.completion_proc"
```

### Step 2: GREEN

- [ ] **Step 2-A: runner.rb に install_completion + 呼出を追加**

`lib/cclikesh/runner.rb` の `RelineDialogs.install(builder)` の前に:

```ruby
install_completion(builder)
RelineDialogs.install(builder)
```

そして `prompt_text` の上に新規メソッド:

```ruby
def self.install_completion(builder)
  return unless builder.on_tab_handler
  Reline.completion_proc = builder.on_tab_handler
end
```

- [ ] **Step 2-B: GREEN 確認**

```bash
bundle exec ruby -Itest -Ilib test/test_on_tab_wiring.rb 2>&1 | tail -5
bundle exec rake test 2>&1 | tail -3
```

期待: failures=0。

- [ ] **Step 2-C: Commit**

```bash
git add lib/cclikesh/runner.rb
git commit -m "feat(runner): wire builder.on_tab_handler into Reline.completion_proc

The on_tab DSL was captured in Builder but never reached Reline. Tab
key now dispatches the user-registered completion block. Runs in main
Ractor (no shareable conversion needed)."
```

---

## Task 12: Thread audit test (priority 4 + 6 原則の自動 enforcement)

**Files:**
- Create: `cclikesh-debug/test/cclikesh-debug/test_thread_zero.rb`
- Create: `test/test_thread_zero.rb` (本体側)

### Step 1: RED — sub-gem の application code に Thread.new 0 件を assert

- [ ] **Step 1-A: sub-gem audit test 新規**

`cclikesh-debug/test/cclikesh-debug/test_thread_zero.rb`:

```ruby
require "test/unit"

class TestThreadZero < Test::Unit::TestCase
  ROOT = File.expand_path("../../..", __dir__)

  def test_no_thread_new_in_application_code
    paths = [
      File.join(ROOT, "cclikesh-debug/lib"),
      File.join(ROOT, "cclikesh-debug/exe")
    ]
    hits = []
    paths.each do |p|
      Dir.glob(File.join(p, "**/*.rb"), File::FNM_DOTMATCH).each do |f|
        next if File.directory?(f)
        File.read(f).each_line.with_index(1) do |line, lineno|
          # Strip simple line comments before grepping.
          stripped = line.sub(/#.*$/, "")
          if stripped =~ /Thread\.(?:new|fork|start)\b/
            hits << "#{f}:#{lineno}: #{line.strip}"
          end
        end
      end
    end
    assert hits.empty?, "Thread禁止 violation:\n#{hits.join("\n")}"
  end
end
```

- [ ] **Step 1-B: 実行**

```bash
cd cclikesh-debug && bundle exec ruby -Itest test/cclikesh-debug/test_thread_zero.rb 2>&1 | tail -5
```

期待: PASS (Task 8〜9 で Thread.new は全廃済)。万が一 hit があれば、それを Task 8/9 に戻して fix。

- [ ] **Step 1-C: 本体 audit test 新規**

`test/test_thread_zero.rb`:

```ruby
require "test/unit"

class TestThreadZero < Test::Unit::TestCase
  ROOT = File.expand_path("..", __dir__)

  def test_no_thread_new_in_application_code
    paths = [
      File.join(ROOT, "lib"),
      File.join(ROOT, "examples")
    ]
    hits = []
    paths.each do |p|
      Dir.glob(File.join(p, "**/*.rb"), File::FNM_DOTMATCH).each do |f|
        next if File.directory?(f)
        File.read(f).each_line.with_index(1) do |line, lineno|
          stripped = line.sub(/#.*$/, "")
          if stripped =~ /Thread\.(?:new|fork|start)\b/
            hits << "#{f}:#{lineno}: #{line.strip}"
          end
        end
      end
    end
    assert hits.empty?, "Thread禁止 violation:\n#{hits.join("\n")}"
  end
end
```

- [ ] **Step 1-D: 全体実行**

```bash
bundle exec rake test 2>&1 | tail -3
cd cclikesh-debug && bundle exec rake test 2>&1 | tail -3
```

期待: 両方 failures=0。

- [ ] **Step 1-E: Commit**

```bash
git add test/test_thread_zero.rb cclikesh-debug/test/cclikesh-debug/test_thread_zero.rb
git commit -m "test: enforce Thread禁止 (design principle #1) via audit greps

Both lib/ (本体) and cclikesh-debug/{lib,exe}/ are scanned for
Thread.new/fork/start. Comments are stripped before grepping. New
violations fail CI immediately."
```

---

## Task 13: Manual smoke checklist (priority 4)

**Files:**
- 触らへん (実機での動作確認のみ)

非 TDD task、commit なし。

- [ ] **Step 1: 本体の echo_shell**

```bash
bundle exec ruby examples/echo_shell.rb
```

確認 (iTerm2 / Apple Terminal で):
- header / footer / info_bar / spinner が描画される
- 数行 input → display_pad に蓄積、Reline.readline は次プロンプトに即戻る
- WINCH (terminal resize) → `Curses::KEY_RESIZE` 受領で全 region 再 paint
- popup (slash menu, ghost text) → 表示・dismiss、stale paint なし
- `/q` で quit → curses teardown 後にプロンプト復帰

- [ ] **Step 2: irb_shell + on_tab**

```bash
bundle exec ruby examples/irb_shell.rb
```

確認:
- tab completion (`String.` で method 候補) が動く (Task 11 の配線)

- [ ] **Step 3: cclikesh-debug E2E (real terminal)**

```bash
dir=$(mktemp -d)
CCLIKESH_DEBUG_DIR=$dir bundle exec exe/cclikesh-debug start examples/echo_shell.rb --no-vector &
START_PID=$!
sleep 2
SESS_LINE=$(grep -m1 session_uuid= /proc/$START_PID/fd/1 2>/dev/null || true)
# macOS の場合は / proc がないので別途 stdout 拾う方法を採用
# 実機では start のターミナルから session_uuid を目視で取る
```

(macOS 上では `/proc` 不可。`start` の stdout を `tee` してファイル経由で uuid を拾うか、`unbuffer` 経由で起動する。本 step は手元 manual な方法でやる)

確認:
- `cclikesh-debug input <s> "hello\r"` → echo
- `cclikesh-debug capture <s>` → frame 1 つ INSERT
- `cclikesh-debug stop <s>` → process 終了
- `cclikesh-debug frames <s>` → 1 行以上の frame 列挙
- `cclikesh-debug semantic <s> "input received"` → vec0 検索結果

問題があれば該当 task に戻して fix。

---

## Final verification

- [ ] **Step 1: 本体・sub-gem 両方の test 実行**

```bash
bundle exec rake test 2>&1 | tail -3
cd cclikesh-debug && bundle exec rake test 2>&1 | tail -3
```

期待: 両方 failures=0。

- [ ] **Step 2: Thread.new audit 最終確認**

```bash
grep -rn "Thread\.\(new\|fork\|start\)" lib/ examples/ cclikesh-debug/lib/ cclikesh-debug/exe/ 2>&1
```

期待: hit 0 件。

- [ ] **Step 3: sqlite3 残骸 audit**

```bash
grep -rn "sqlite3\|SQLite3" cclikesh-debug/lib/ cclikesh-debug/exe/ 2>&1
```

期待: hit 0 件 (Storage / StorageWriter / EmbedStorageWriter は extralite のみ)。

- [ ] **Step 4: branch state 確認**

```bash
git log --oneline main..HEAD | head -30
```

期待: 各 task ごと RED/GREEN コミットが残ってる、TDD 物証。

- [ ] **Step 5: PR 用の summary をローカルメモ**

各 task の commit hash と「何が変わったか」を 1 行で書き出して PR description 草稿に流す。

---

## 6 原則チェックシート (各 task PR 時に確認)

- [ ] Thread.new / Thread.fork / Thread.start を application code で使ってない
- [ ] 並行・並列が必要な箇所はすべて `Ractor.new` + `Ractor::Port`
- [ ] Ractor unsafe な C 拡張 (sqlite3-ruby、informers) は別プロセス + DRb で隔離
- [ ] DB connection / socket / IO は Ractor の中で open している
- [ ] `Ractor::Port#send` で渡す Hash / Array / String は再帰的に frozen
- [ ] `#take` / `#yield` を使ってない (Ruby 4.0+ API のみ)
