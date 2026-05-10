# cclikesh recorder pipeline Ractor 再設計 + 周辺 priority 1〜4

## Goal

cclikesh-debug の recorder pipeline を「sqlite3 が Ractor unsafe やから StorageWriter を Thread 降格」案を**棄却**し、**all-Ractor + Thread 完全禁止**で再設計する。あわせて handoff の priority 2〜4 (E2E test TTY、on_tab DSL Reline 配線、manual smoke) を同 design doc に統合する。

設計原則: **シンプル / 浅レイヤー / Thread 禁止 / well-known ライブラリ活用 / 自作コード最小化**。

## 起点となる事実関係

- **`Ractor::UnsafeError` は C-method の marking 問題**。rurema 出典: 「Raised when Ractor-unsafe C-methods is invoked by a non-main Ractor」
- **sqlite3-ruby は 2021 年から audit 未着手** ([Issue #299](https://github.com/sparklemotion/sqlite3-ruby/issues/299))。`rb_ext_ractor_safe(true)` の宣言なし。これは sqlite3 の問題ではなく **gem の問題**
- **extralite は明示的に Ractor-safe** (README: 「Extralite databases can safely be used inside ractors」、GVL 解放も設定可能、Ruby 3.0+ 対応)。DB ファイル形式は SQLite 標準なので chiebukuro-mcp との互換性に影響なし
- **sqlite-vec は driver-agnostic**。`SqliteVec.loadable_path` で extension file path を取得できる。`SqliteVec.load(db)` は内部で `db.load_extension(path)` を呼ぶだけ。extralite でも `db.load_extension(SqliteVec.loadable_path)` で動作する想定
- **Ruby 4.0 Ractor API 確定**: `Ractor::Port` 導入、`#take`/`#yield` 廃止、`Ractor.shareable_proc(&block)`、`Ractor.receive` (内部)、`port.receive` / `port.send`
- **informers (ONNX Runtime ラッパー) の Ractor 適合は未確定**。Probe で確認、Case A / Case B の二分岐設計

## Ractor 設計原則 (本プロジェクト全体に適用)

| # | 原則 | 適用 |
|---|------|------|
| 1 | **Thread 禁止** | application code で `Thread.new` を書かへん。Ruby 標準ライブラリ・gem (DRb 内部 etc) が thread を使うのは許容 |
| 2 | **Ractor が第一級** | 並行・並列が必要な場面はすべて `Ractor.new`、`Ractor::Port` と `shareable_proc` で message passing |
| 3 | **Ractor unsafe な C 拡張は別プロセス + DRb** | sqlite3-ruby (audit 未) や informers (probe NG の場合) は別プロセス起動 + DRb 越し RPC。Thread フォールバック禁止 |
| 4 | **Unshareable resource は Ractor 内で open** | DB connection、socket、IO は Ractor 生成・消費を完結。`extralite` が公式 Ractor-safe SQLite 唯一の選択 |
| 5 | **Message は frozen / shareable のみ** | `Ractor::Port#send` で渡す Hash は値も再帰的に shareable、`deep_freeze` ヘルパで保証 |
| 6 | **Ruby 4.0+ API のみ** | `Ractor::Port`、`Ractor.shareable_proc(&block)`、`Ractor.receive`。古い `#take`/`#yield`/`make_shareable(proc, copy: true)` は使わへん |

## Scope

### In scope

1. **Recorder pipeline 再設計** (priority 1): sqlite3 → extralite 移行 + 3 段 Ractor pipeline
2. **Embedder 戦略**: Case A (informers Ractor 内 OK) / Case B (subprocess + DRb) の probe-driven 分岐
3. **本体 cclikesh の Thread 禁止徹底**: Thread.new audit、debug_endpoint の DRb 内部 thread 例外扱い明記
4. **E2E test TTY 戦略** (priority 2): PTY allocate での TTY 確保
5. **on_tab DSL → Reline 配線** (priority 3): `Reline.completion_proc` 経由で fan-out
6. **Manual smoke checklist** (priority 4): iTerm2 実機確認手順
7. **migration path**: sqlite3 → extralite の Storage クラス内部 API 書換マップ

### Out of scope

- chiebukuro-mcp の改修 (DB ファイル形式互換のため不要)
- sqlite3-ruby に Ractor-safe audit PR を投げる活動 (long-term、別 issue)
- web viewer / replay subcommand
- 多 session 集約 query

## Section 2: Recorder pipeline 再設計 (priority 1)

### Pipeline 構造 (live 中)

```
┌─────────────────────────────────────────────────────────────────┐
│ cclikesh-debug daemon (1 プロセス)                              │
│                                                                  │
│   ┌──────────────┐  port   ┌──────────────┐  port              │
│   │ PtyReader    │────────▶│ FrameBuilder │──────┐              │
│   │ Ractor       │ [:bytes,│ Ractor       │      │              │
│   │              │  chunk, │              │      │              │
│   │ PTY master   │  ts]    │ raw buffer + │      │              │
│   │ read_nonblock│         │ snapshot →   │      │              │
│   └──────────────┘         │ frame data   │      │              │
│         ▲                  └──────────────┘      │              │
│         │                                         ▼              │
│   ┌──────────────────────────────────┐  port  ┌───────────────┐ │
│   │ Orchestrator (main Ractor)       │───────▶│ StorageWriter │ │
│   │  - DRb.connect (cclikesh shell)  │[:frame,│ Ractor        │ │
│   │  - debug_snapshot pull           │  data] │               │ │
│   │  - capture trigger fan-out       │        │ extralite db  │ │
│   │  - control socket listener       │        │ Ractor 内 open │ │
│   └──────────────────────────────────┘        └───────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

3 段 (PtyReader / FrameBuilder / StorageWriter)。Embedder は live pipeline に**含めない** (post-process bulk 確定)。Orchestrator は main Ractor で DRb 窓口を担う (DRb は Ractor 内不可)。

### 各 Ractor の責務と message protocol

**PtyReader**
- 生成: `master_fd: Integer` を引数で受領
- 出力 port: `[:bytes, frozen_chunk_string, ts_float]`、EOF/EIO で `[:eof]`
- 内部: `IO.for_fd(fd, "rb", autoclose: false)` + `read_nonblock(64KB)` ループ。chunk は `freeze` 必須

**FrameBuilder**
- 入力: PtyReader port から `[:bytes, chunk, ts]`、Orchestrator から `[:capture_with_snapshot, trigger, event_kind, snapshot]`
- 出力 port: `[:frame, frozen_frame_hash]`
- 内部: `raw_buffer = +"".b` 蓄積、capture trigger 受領で `framework_state` から `content` を build → frame data を `freeze` して送出 → buffer clear

**StorageWriter**
- 生成: `db_path: String` (frozen) を引数で受領
- 入力 port: `[:frame, frame_hash]`、`[:eof] | [:stop]`
- 内部: Ractor 内で `Extralite::Database.new(path)` + `db.load_extension(SqliteVec.loadable_path)` + INSERT
- `Ractor::Port` で main Ractor 側からの port を受け取り、`port.receive` で消費

### sqlite3 → extralite API 対応表

| 旧 (sqlite3 + sqlite_vec) | 新 (extralite + sqlite_vec) |
|---|---|
| `SQLite3::Database.new(path)` | `Extralite::Database.new(path)` |
| `db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)` | `db.load_extension(SqliteVec.loadable_path)` |
| `db.execute("PRAGMA journal_mode = WAL")` | 同 |
| `db.execute_batch(SCHEMA)` | `db.execute_multi(SCHEMA)` |
| `db.execute(sql, [args])` | `db.execute(sql, *args)` (positional) |
| `db.last_insert_row_id` | `db.last_insert_rowid` |
| `db.execute(sql).first` | `db.query_single_row(sql)` または `db.query(sql).first` |
| `SQLite3::Database.new(path, readonly: true)` | `Extralite::Database.new(path, read_only: true)` |

`Storage` クラスの**外部 API は不変**。内部の `@db.execute` 呼出を全部書き換えるだけ。chiebukuro-mcp は sqlite3-ruby で読むが DB ファイル形式は標準 SQLite やから互換性影響なし。

### Orchestrator (main Ractor) の役割

```ruby
class Cclikesh::Debug::Recorder
  def start_pipeline!(pty_master_fd:, drb_uri:)
    @drb_proxy = DRbObject.new_with_uri(drb_uri)  # main Ractor 専有

    @storage_port = Ractors::StorageWriter.spawn(db_path: @storage.path)
    @frame_port   = Ractors::FrameBuilder.spawn(downstream: @storage_port)
    @pty_port     = Ractors::PtyReader.spawn(downstream: @frame_port, master_fd: pty_master_fd)
  end

  def trigger_capture!(trigger: "on_demand", event_kind: nil)
    snap = @drb_proxy.debug_snapshot                  # DRb pull は main Ractor で
    frozen = deep_freeze(snap)                         # 値も再帰的に shareable に
    @frame_port.send([:capture_with_snapshot,
                       trigger.to_s.freeze,
                       event_kind&.to_s&.freeze,
                       frozen])
  end

  def stop!
    [@pty_port, @frame_port, @storage_port].each { |p| p.send([:stop]) rescue nil }
    embed_pending!  # post-process bulk
  end

  private

  def deep_freeze(obj)
    case obj
    when Hash    then obj.transform_values { |v| deep_freeze(v) }.freeze
    when Array   then obj.map { |v| deep_freeze(v) }.freeze
    when String  then obj.frozen? ? obj : obj.dup.freeze
    else obj
    end
  end
end
```

`@drb_proxy` は main Ractor で握る。Hash/Array/String を再帰的に freeze してから FrameBuilder の port に送出する。

### Synthetic frame path

test-only の `synthetic_frame!` は main Ractor 内で `FrameBuilder` port に直接 `[:capture_with_snapshot, ...]` 送出 → StorageWriter port に流す形に書換。`drain_one_cycle!` の同期動作は port の round-trip で実現 (StorageWriter から ack port を一段挟む)。

## Section 3: Embedder 戦略 (probe-driven)

### Probe (Plan Task 0)

```ruby
# tmp/probes/probe_informers_ractor.rb (committable; プロジェクト方針確認用)
require 'informers'

r = Ractor.new do
  model = Informers.pipeline('feature-extraction', 'mochiya98/ruri-v3-310m-onnx')
  vec = model.('テスト', model_output: 'sentence_embedding', normalize: true).flatten
  [vec.size, vec.first.class]
end
p r.value  # 期待: [768, Float]、Ractor::UnsafeError or SEGV を観察
```

判定:
- ✅ Pass → **Case A** (Embedder Ractor)
- ❌ Fail → **Case B** (subprocess + DRb)

### Case A: Embedder Ractor

```ruby
# cclikesh-debug/lib/cclikesh/debug/ractors/embedder.rb
module Cclikesh::Debug::Ractors::Embedder
  def self.spawn(db_path:)
    Ractor.new(db_path) do |path|
      require 'extralite'
      require 'informers'
      require 'sqlite_vec'

      db = Extralite::Database.new(path)
      db.load_extension(SqliteVec.loadable_path)
      model = Informers.pipeline('feature-extraction', 'mochiya98/ruri-v3-310m-onnx')

      loop do
        msg = Ractor.receive
        case msg
        in [:embed, frame_id, content]
          vec = model.(content, model_output: 'sentence_embedding', normalize: true).flatten
          db.execute("INSERT OR REPLACE INTO frame_vec(frame_id, embedding) VALUES (?, ?)",
                     frame_id, vec.pack("f*"))
        in [:stop]
          break
        end
      end
    ensure
      db&.close
    end
  end
end
```

Recorder の `embed_pending!` は Embedder Ractor を spawn → 未 embed の frame を順次 send → `:stop`。

### Case B: subprocess + DRb (Thread フォールバック禁止対応)

別プロセスで informers を隔離。DRb は **well-known な標準ライブラリ** やから自作コード最小化の方針に合致。

```
┌──────────────────────────────┐         ┌────────────────────────┐
│ cclikesh-debug daemon        │ DRb     │ embedder subprocess    │
│  - main Ractor で DRb proxy  │────────▶│  - Informers.pipeline  │
│  - EmbedStorageWriter Ractor │         │  - DRb server          │
│    (extralite に vec INSERT) │         │  - drbunix 経由 1on1   │
└──────────────────────────────┘         └────────────────────────┘
```

**embedder subprocess** (`cclikesh-debug/exe/cclikesh-debug-embedder`):

```ruby
#!/usr/bin/env ruby
require 'drb/drb'
require 'informers'

class EmbedderService
  include DRb::DRbUndumped
  def initialize
    @model = Informers.pipeline('feature-extraction', 'mochiya98/ruri-v3-310m-onnx')
  end
  def embed(content)
    @model.(content, model_output: 'sentence_embedding', normalize: true).flatten
  end
end

sock = ARGV[0] or abort 'usage: cclikesh-debug-embedder <unix-sock-path>'
DRb.start_service("drbunix:#{sock}", EmbedderService.new)
DRb.thread.join
```

**recorder 側** `embed_pending!`:

```ruby
def embed_pending!
  return if @no_vector

  sock = "tmp/cclikesh-debug/embedder-#{Process.pid}.sock"
  pid = Process.spawn("cclikesh-debug-embedder", sock,
                      out: "tmp/cclikesh-debug/embedder.log", err: [:child, :out])
  wait_for_socket(sock)
  proxy = DRbObject.new_with_uri("drbunix:#{sock}")

  port = Ractors::EmbedStorageWriter.spawn(db_path: @storage.path)
  @storage.db.query("SELECT f.id, f.content FROM frames f
                       LEFT JOIN frame_vec v ON v.frame_id = f.id
                      WHERE v.frame_id IS NULL").each do |r|
    vec = proxy.embed(r[:content])              # DRb 呼出は main Ractor
    port.send([:write, r[:id], vec.pack("f*").freeze])
  end
  port.send([:stop])
ensure
  Process.kill('TERM', pid) if pid
  File.unlink(sock) if File.exist?(sock)
end
```

`EmbedStorageWriter` は extralite に書込専用の薄い Ractor (vec の bytes を受領して `frame_vec` に INSERT)。DRb は main Ractor で握る。**Thread はゼロ**。

### 不変条件 (両 case 共通)

- `embed_pending!` の外部 API は不変 (caller は case を意識せえへん)
- live pipeline には embedder を含めへん (3 段純粋を維持)
- DB 書込は Ractor 内に閉じる
- DRb 操作は main Ractor のみ
- subprocess 起動は ONNX SEGV からの隔離も兼ねる

## Section 4: 本体 cclikesh の Thread 禁止徹底

### Audit ルール

- `grep -rn "Thread\.new\|Thread\.fork" lib/ examples/ cclikesh-debug/lib/ cclikesh-debug/exe/` が **0 件** であることを CI 相当で確認
- 例外として **DRb 内部の thread** (DRb.start_service が裏で thread を立てる) は許容 — application code が直接 `Thread.new` を呼ぶことは禁止
- `Signal.trap` の handler 内でも Thread を作らへん

### debug_endpoint.rb の扱い

- 現状: `ENV['CCLIKESH_DEBUG_SOCK']` set 時のみ `DRb.start_service`、Adapter は Mutex で event queue を guard
- これは「Ruby 標準ライブラリが thread 使うのは許容」の例外に該当 → そのまま維持
- ただし application code が Adapter を Thread でラップしたり Mutex を独自に追加するのは禁止 — 必要なら Ractor + port に移行

## Section 5: E2E test TTY 戦略 (priority 2)

### 現状の不具合

`bundle exec ruby` で起動した child process に TTY が無く、`Curses.init_screen` が `cannot open terminal` で即死。`test_e2e_full_session.rb` が omit 状態。

### 解: PTY.open + Process.spawn

Ruby 標準 `PTY.open` で master/slave 取って、`Process.spawn` の `in:/out:/err:` に slave を渡す (env hash も Process.spawn が受ける)。`PTY.spawn` は env hash 非対応やから採用しない。well-known ライブラリ活用、自作コードゼロ。

```ruby
require 'pty'

master, slave = PTY.open
pid = Process.spawn(
  { 'TERM' => 'xterm-256color', 'LINES' => '24', 'COLUMNS' => '80' },
  'bundle', 'exec', 'ruby', 'examples/echo_shell.rb',
  in: slave, out: slave, err: slave
)
slave.close  # 親側は master だけ保持

master.write("hello\r")
output = master.read_nonblock(4096) rescue ""
Process.kill('TERM', pid)
Process.wait(pid)
master.close
```

これで `Curses.init_screen` は slave PTY を TTY として認識する。`ENV['TERM']` も明示。

### Fallback: rake task 分離

PTY allocate でも環境差で動かんケース (CI 上の TTY 周り) があれば、`rake test:integration` に分離して `rake test` のデフォルトからは除外。`bundle exec rake test:integration` で手動実行。

### 採用方針

PTY allocate を**先に試行**、ローカル macOS で動けば採用。動かんかったら分離。両方の道は spec で残しておく。

## Section 6: on_tab DSL → Reline tab completion 配線 (priority 3)

### 現状

`Cclikesh::Builder` で `on_tab { |word| [...] }` block を capture してるが、`runner.rb` の Reline 設定時に `Reline.completion_proc` に流してへん。Tab 押しても何も起こらん。

### 解

```ruby
# lib/cclikesh/runner.rb
def self.run(builder)
  init_curses!
  Cclikesh::Style.init!
  ...

  if builder.on_tab_handler
    Reline.completion_proc = builder.on_tab_handler  # main Ractor で実行、shareable 不要
  end

  ...
end
```

`on_tab_handler` は word を受け取って候補配列を返す `Proc`。main Ractor 内で評価されるので shareable 化不要。

### Examples 追加

`examples/irb_shell.rb` の `IrbCompleter` を on_tab に配線:

```ruby
shell.on_tab do |word|
  ctx.shareable(:completer).call(:complete, word)
end
```

`State Ractor` (`shareable_ref`) 経由で IrbCompleter を呼ぶ場合は port の同期 RPC で結果を取る。

## Section 7: Manual smoke checklist + migration path (priority 4)

### Manual smoke checklist (iTerm2 / Apple Terminal で手動確認)

- [ ] `bundle exec ruby examples/echo_shell.rb` 起動 → header/footer/info_bar/spinner が描画される
- [ ] 数行 input → display_pad に蓄積、Reline.readline は次のプロンプトに即戻る
- [ ] WINCH (terminal resize) → `Curses::KEY_RESIZE` 受領で全 region 再 paint
- [ ] popup (slash menu, ghost text) → 表示・dismiss 確認、stale paint なし
- [ ] `/q` で quit → curses teardown 後にプロンプト復帰
- [ ] `bundle exec ruby examples/irb_shell.rb` 起動 → tab completion (`String.` → method 候補) 動作
- [ ] `bundle exec exe/cclikesh-debug start examples/echo_shell.rb` で recorder daemon 起動 → `cclikesh-debug input <s> "hello\r"` → `cclikesh-debug capture <s>` → `cclikesh-debug stop <s>` → `cclikesh-debug frames <s>` で frame 取得確認
- [ ] `cclikesh-debug semantic <s> "input received"` で sqlite-vec 検索が結果返す

### Migration path (sqlite3 → extralite)

1. `cclikesh-debug.gemspec`: `add_dependency 'sqlite3'` を `add_dependency 'extralite', '~> 2.12'` に置換
2. `Gemfile.lock` 再生成 (`bundle update extralite`)
3. `cclikesh-debug/lib/cclikesh/debug/storage.rb` の API 書換 (上記対応表)
4. `cclikesh-debug/lib/cclikesh/debug/ractors/storage_writer.rb` の `require "sqlite3"` を `require "extralite"` に
5. `test_storage.rb` を extralite 期待値に修正 (`db.execute` の args 形式違いだけ)
6. `cclikesh-debug/lib/cclikesh/debug/viewer/*.rb` の DB 操作も extralite に置換 (read_only)
7. chiebukuro-mcp 互換性: DB ファイル形式は標準 SQLite やから無修正

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| extralite で sqlite-vec がうまく load できない | `db.load_extension(SqliteVec.loadable_path)` を probe で先に確認、ダメならパス補正 |
| extralite の API が想定外 (positional vs array args 等) | spec の対応表を migration で都度確認、test を先に書く |
| informers Ractor 内で SEGV | Probe で確認 → Case B (subprocess + DRb) に switch |
| DRb subprocess の lifecycle (orphan 化) | `Process.spawn` の親プロセス監視 + `at_exit` で kill、sock cleanup |
| PTY allocate で TTY 取れず E2E test が動かん | rake task 分離して手動実行扱い |
| chiebukuro-mcp 側の sqlite3 が VEC table 読めない | DB ファイル形式は SQLite 標準、sqlite-vec の vec0 virtual table は SqliteVec.load 後ならどの driver でも見える |

## Test 戦略

### 本体 cclikesh

- 既存 ~120 tests は curses + Ractor 移行済で pass している (handoff 確認済)。本 design では本体側に行動追加しない (priority 3 の on_tab 配線で 1 test のみ追加)
- `test_runner_on_tab.rb` (新規): on_tab handler が Reline.completion_proc に渡るかの assertion

### sub-gem cclikesh-debug

- `test_storage.rb`: extralite 移行に伴い `db.execute` 形式調整、内容は同じ schema/insert/select を assert
- `test_recorder_pipeline.rb`: 3 段 Ractor pipeline を synthetic 入力で 1 cycle 回す、StorageWriter Ractor 内 extralite 動作確認
- `test_embedder.rb`: Case A 採用なら Embedder Ractor の embed → INSERT を確認、Case B 採用なら DRb proxy stub の embed RPC + EmbedStorageWriter Ractor を確認
- `test_e2e_full_session.rb`: PTY.spawn で TTY 確保 → input → capture → stop → frame SELECT を assert (priority 2 の解決)
- `test_thread_zero.rb` (新規): `grep -rn "Thread\.new\|Thread\.fork" lib/ exe/` で 0 件を assert (priority 4 の Thread 禁止 audit)

## Out of scope (v2 以降)

- chiebukuro-mcp 側の sqlite3 → extralite 移行 (read 専用なので必要性低)
- web viewer / replay subcommand
- 多 session 集約 query
- handler の cancel / retry プリミティブ
- mouse interaction
- sqlite3-ruby に Ractor-safe audit PR を投げる活動 (long-term)
