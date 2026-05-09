# cclikesh — Claude Code 風 CLI インタラクティブシェル フレームワーク 設計書

- 日付: 2026-05-09
- ステータス: 設計確定（実装計画は別ドキュメント）
- 対象 Ruby: 4.0.3+

## 1. 概要

`cclikesh` は Claude Code 風の 3 区分 CLI インタフェース（display / input / info）を提供する Ruby フレームワーク。フレームワーク本体は描画・イベントループ・接合 DSL のみを担当し、impl 側はピュア Ruby でビジネスロジック・I/O を書ける。

### 1.1 設計上の主たる原則

- **impl 側はピュア Ruby**。DSL 依存はフレームワーク接合面のみ。
- **継承不要**。impl はフレームワーク提供のクラスを継承しない。
- **ブロック渡し中心の DSL**。Sinatra の `configure { |c| ... }` 風、ただし block 引数 `shell` で明示。
- **Minimal Core**。`/quit` などの組み込み slash も持たない。便利機能は将来 extras に。
- **観測性は core の責務**。Ruby 標準 `Logger` 互換のロギングを最初から提供する。
- **黒魔術は隔離**。フレームワーク内部の reline/irb 関連の monkey patch 等は `Ruby::Box` に閉じる。
- **impl と F は別プロセス**で dRuby 越しに通信。Ractor は F 内部の並行性。
- **ts4r (TupleSpace4Ractor) を全通信の中央**に置く。Ractor 間も impl-F 間も同じ I/F。

## 2. アーキテクチャ全体図

```
┌──────────────────────────────────────────────────────────┐
│                    impl 層 (pure Ruby)                   │
│  - ビジネスロジック (例: irb の Ruby 評価, completer)    │
│  - IO ロジック (file load, network)                      │
│  - 値オブジェクト・カウンタ・state 保持                  │
└──────────────────┬───────────────────────────────────────┘
                   │
            ── DSL 接合面 ──
            ┌──────────────────────────────────────────┐
            │ Cclikesh.run do |shell|                  │
            │   shell.on_submit { |line, ctx| ... }    │
            │   shell.on_tab    { |buf, pos, ctx| ... }│
            │   shell.info(name) { ... }               │
            │   shell.slash(name) { |args, ctx| ... }  │
            │   shell.spinner_label { ... }            │
            │ end                                      │
            │                                          │
            │ ctx.display.append(...)                  │
            │ ctx.display.open_live { |slot| ... }     │
            │ ctx.dialog.show(...) / .close            │
            │ ctx.state[:key] / ctx.state[:key]= ...   │
            └──────────────────────┬───────────────────┘
                                   │  dRuby (UNIX socket)
┌──────────────────────────────────▼───────────────────────┐
│           F process (Ractor 群 + ts4r)                   │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Cclikesh::TupleSpace (ts4r ベース、dRuby front)    │  │
│  │   全通信が tuple write/take で完結                 │  │
│  └─────────┬──────────┬──────────┬─────────────────┘     │
│            │          │          │                       │
│  ┌─────────▼──┐ ┌─────▼────┐ ┌───▼───────┐               │
│  │ Input R    │ │ Render R │ │ Logger R  │               │
│  │ STDIN 読み │ │ 60ms tick│ │ ts.log_take│              │
│  └────────────┘ └──────────┘ └───────────┘               │
│  ┌──────────────────────────────────────────┐            │
│  │ Main R (dispatcher + DRb front for ctx)  │            │
│  └──────────────────────────────────────────┘            │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │ Ruby::Box (F-internal isolation)                 │    │
│  │  reline / irb 関連 require と monkey patch       │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

### 2.1 境界の引き方

- **impl と F は別プロセス**。`ruby my_impl.rb` で起動 → `Cclikesh.run` が F を fork+exec する。F が terminal 制御を握る。
- **Ruby::Box** は F 内部で reline/irb 等が触る monkey patch を閉じる目的のみ。impl-F 隔離は dRuby の物理境界が担う。
- **ts4r** は F 内部の中央通信ハブ。dRuby 公開もここから行うため impl も同じ tuple I/F でアクセス可能。

## 3. 公開 API（DSL surface）

### 3.1 エントリポイント

```ruby
Cclikesh.run do |shell|
  # 登録のみ。block 終了で event loop 起動（blocking）。
end
```

block 抜けたあと validation → F 起動 → 描画ループ。`Cclikesh.run` は ctrl-c / `ctx.quit` まで戻らない。

### 3.2 Builder (`shell`) のメソッド

| メソッド | block 引数 | 用途 | 多重登録 |
|---|---|---|---|
| `shell.on_submit` | `(line, ctx)` | Enter 押下時の主処理 | 1回のみ |
| `shell.on_tab` | `(buf, pos, ctx)` | Tab 押下時 | 1回のみ |
| `shell.on_state_change` | `(key, old, new, ctx)` | state 変化時 | 1回のみ |
| `shell.on_start` | `(ctx)` | event loop 起動直後 | 複数 (登録順) |
| `shell.on_quit` | `(ctx)` | event loop 終了直前 | 複数 (逆順) |
| `shell.before_submit` | `(line, ctx)` | on_submit 直前 | 複数 |
| `shell.after_submit` | `(line, ctx)` | on_submit 直後 | 複数 |
| `shell.before_tab` | `(buf, pos, ctx)` | on_tab 直前 | 複数 |
| `shell.after_tab` | `(buf, pos, candidates, ctx)` | on_tab 直後 | 複数 |
| `shell.info(name, order: nil)` | なし → 文字列 | info 領域 segment | 複数 |
| `shell.spinner_label` | なし → 文字列 or `:auto` or `nil` | spinner 横 label | 1回のみ |
| `shell.slash(name)` | `(args, ctx)` | slash 命令 | 名前ごと |
| `shell.idle_phrases` / `=` | — | アイドル中の遊び表示語彙 | — |
| `shell.idle_phrase_interval` | — | 切替周期（秒） | — |
| `shell.logger` / `=` | — | Ruby Logger 互換インスタンス | — |
| `shell.log_level` / `=` | — | `:debug` `:info` `:warn` `:error` | — |
| `shell.log_to(path_or_io)` | — | 出力先 setter | — |
| `shell.tick_interval` / `=` | — | 描画 tick 周期（秒、デフォルト 0.06） | — |
| `shell.define_style(name, **opts)` | — | display 用 style 追加 | — |

### 3.3 ctx (runtime context) API

callback の最後の引数として常に渡る。impl から F への唯一の通信路。

```ruby
ctx.display.append(text, style: nil, prompt: nil)
ctx.display.open_live(style: nil) { |slot| ... }   # block 形式（推奨）
ctx.display.open_live(style: nil)                  # 明示形式: slot 返却

ctx.dialog.show(content, style: nil)
ctx.dialog.close

ctx.state[:key]
ctx.state[:key] = value
ctx.state.update(hash)
ctx.state.delete(:key)
ctx.state.to_h

ctx.logger.debug/info/warn/error/fatal(...)

ctx.quit                                           # event loop 終了要求
ctx.refresh                                        # 強制再描画
```

### 3.4 設計上の決め

- `shell` は `Cclikesh::Builder` のインスタンス（Box 内）
- impl は Builder を継承しない、メソッドを呼ぶだけ
- `ctx` は callback 毎に同一インスタンスが渡る（中身は dRuby proxy）
- block の戻り値は基本無視、push API のため。例外は `on_tab`（補完候補配列を返す必要、reline へ橋渡し）

### 3.5 やらないこと

- middleware パイプライン
- 名前付き event の publish/subscribe（state injection で代替）
- multiple shell 並走

## 4. Runtime / Lifecycle

### 4.1 起動から終了

```
[1] Cclikesh.run { |shell| ... }
[2] Builder block 実行 → registration
[3] Runtime 構築
    - logger, reline, 3-region renderer 初期化
    - state store, signal trap, on_start hooks
    - F process fork + tcsetpgrp 譲渡
[4] Main event loop
    - render tick (60ms)
    - input poll (reline)
    - tuple イベント dispatch
    - state change 検知
    - quit 要求検知
[5] Shutdown
    - on_quit hooks (逆順)
    - reline cleanup, alternate screen 復帰
    - logger flush
[6] Cclikesh.run リターン
```

### 4.2 描画 tick

- デフォルト 60ms（≒17fps）。spinner / elapsed の自然な滑らかさの最低ライン。
- `shell.tick_interval = 0.1` で変更可。
- `ctx.refresh` で次 tick を待たず即時再描画。

### 4.3 reline 統合

- 入力領域は完全に reline 委譲。F は `Reline::LineEditor` を Box 内で構築、表示位置を下端に固定。
- F が dispatch を上書きするのは Tab のみ。`on_tab` 経由で処理してから reline の補完表示にも流す。
- `on_tab` の戻り値（候補配列）を reline に渡し、reline が「複数候補なら表示、単一なら確定」を担当。
- 補完 dialog の見た目は F の dialog primitive で差し替え可能。

### 4.4 signal handling

| signal | 挙動 |
|---|---|
| `SIGINT` (Ctrl-C) | 入力中なら入力クリア、空入力中なら quit |
| `SIGTERM` | 即 quit (on_quit は呼ぶ) |
| `SIGWINCH` | 端末リサイズ → 全領域再計算 |
| `SIGTSTP` (Ctrl-Z) | reline 標準動作 (suspend) |

### 4.5 quit パス

3 経路すべて同じ shutdown sequence へ集約:

1. signal: main loop で flag 検知して break
2. `ctx.quit`: flag 立てて current callback 完了後 break
3. slash で `/quit`: impl が `ctx.quit` を呼ぶ実装

### 4.6 並行性モデル: Ractor + dRuby + ts4r

#### トポロジー

```
F process
  Cclikesh::TupleSpace (ts4r、dRuby front)
    Input Ractor    write [:key, ...]
    Render Ractor   take [:render, ...] (60ms tick + 即時取り出し coalesce)
    Logger Ractor   ts.log_take で集約 → Logger format で stderr
    Main Ractor     dispatcher、ctx を DRb front 化
       │
       │ dRuby (UNIX socket)
       ▼
impl process
  DRbObject.new_with_uri(...)
  HandlerRegistry を DRb-front 化、F が remote call
  callback 内では ctx (DRb proxy) で F 操作
```

#### 起動フロー

`ruby my_impl.rb` で起動:

1. impl process（parent）が `Cclikesh.run` を呼ぶ
2. fork → child = F process
3. child で `exec` し cclikesh-renderer 相当のコード起動、env 経由で UNIX socket path 共有
4. parent は HandlerRegistry を DRb-front、child の F が DRbObject 経由で接続
5. tcsetpgrp で child に terminal 制御を譲渡
6. parent は DRb 待ち受けループに入る、callback は dRuby 経由で着信

#### Tuple スキーマ

| pattern | 書き手 | 読み手 |
|---|---|---|
| `[:key, key_obj]` | Input R | Main R |
| `[:event, :submit, line]` | Main R | impl |
| `[:event, :tab, buf, pos]` | Main R | impl |
| `[:event, :slash, name, args]` | Main R | impl |
| `[:event, :state_change, key, old, new]` | Main R | impl |
| `[:event, :start]` / `[:event, :quit]` | Main R | impl |
| `[:result, :tab, candidates]` | impl | Main R |
| `[:render, :display_append, text, opts]` | impl, Main R | Render R |
| `[:render, :live_open, slot_id, opts]` | impl | Render R |
| `[:render, :live_update, slot_id, text]` | impl | Render R |
| `[:render, :live_commit, slot_id, final]` | impl | Render R |
| `[:render, :info, name, value]` | Main R | Render R |
| `[:render, :spinner_label, value]` | Main R | Render R |
| `[:render, :dialog, action, payload]` | impl | Render R |
| `[:state, :read, key, port]` / `[:state, :write, key, val]` | impl | Main R |
| `[:cmd, :quit]` | impl, Main R | 全員 |
| ts4r `ts.log(...)` 経由 | 全員 | Logger R |

#### イベント圧縮

ts4r の `take` をループで空になるまで取り続け、Render R は frame 開始時に同種 tuple を最新値で集約してから 1 度だけ描画する。

## 5. Display 領域（append + live slot）

### 5.1 2 モード

- **append**: 1 回 push → 確定、history を流れていく
- **live slot**: 1 つの「枠」を impl が握って何度でも更新、`commit` で history 化

```
┌─────────────────────────────────────────┐
│ irb> x = 1                              │ ← append
│ => 1                                    │ ← append
│ irb> heavy_calc                         │ ← append
│ ⠋ Roosting... 8m 54s · 34.6kb           │ ← live slot
└─────────────────────────────────────────┘
                ↑ 入力欄はこの下
```

### 5.2 API

```ruby
ctx.display.append(text, style: :default, prompt: nil)

# block 形式（推奨）
ctx.display.open_live(style: :thinking) do |slot|
  loop_progress { |t| slot.update("Roosting... #{t}s") }
end  # 自動 commit、例外時は自動 discard

# 明示形式
slot = ctx.display.open_live(style: :thinking)
slot.update("...")
slot.commit               # or slot.discard / slot.commit_as(text)
```

### 5.3 制約

- 1 ctx あたり同時に live slot は 1 つまで。2 つめ open は前を auto-commit してから。
- commit/discard 後の操作は no-op（warn ログ）。
- `slot.update` は thread-safe（impl が Thread から触る前提）。

### 5.4 描画

Render R は tick ごとに「history line array + live slot text」を結合。live slot は端末最下行（input 欄の直前）固定、ANSI で行クリア + 上書き。commit 時は live 内容を history array に追加。

### 5.5 style

- F 提供の組み合わせ名: `:default` `:result` `:error` `:prompt` `:thinking` `:dim`
- impl 拡張: `shell.define_style(:my_style, fg: :cyan, bold: true)`
- syntax highlighting は impl 責務（F は色＋装飾の組まで）

## 6. Info 領域 + spinner + slash command

### 6.1 info 領域レイアウト

```
[spinner_frame] [spinner_label]  ([segment1] · [segment2] · ...)
```

例: `✻ Roosting…  (8m 54s · ↓ 34.6kb · 2 jobs)`

### 6.2 spinner

```ruby
shell.spinner do |s|
  s.frames = %w[✻ ✶ ✷ ✸ ✹]
  s.colors = [:cyan, :magenta]
  s.frame_interval = 0.15
end

shell.spinner_label do
  case ctx.state[:phase]
  when :working then :auto              # idle_phrases からランダム
  when :awaiting then "Awaiting input"  # 固定
  else nil                               # spinner 非表示
  end
end
```

`spinner_label` 未登録 → 自動で `:auto` 相当（idle_phrases）動作。

### 6.3 idle_phrases（標準搭載）

「考え中の意味ありげな謎ワード」を切り替え表示する遊び表示。

- `shell.idle_phrases` で配列取得・上書き・追加可能
- `shell.idle_phrase_interval` で切替周期（デフォルト 3 秒）
- 切替は Render R が自前タイマーで管理（dRuby 呼び出しなし、軽量）
- 単語リストは `lib/cclikesh/idle_phrases.txt` に置く

初期セット案:
```
Roosting     Cogitating    Pondering     Galumphing
Schmoozing   Marinating    Percolating   Gestating
Brewing      Conjuring     Munching      Dreaming
Fermenting   Noodling      Simmering     Mulling
Whittling    Composing     Doodling      Mooching
```

### 6.4 segments

```ruby
shell.info(:elapsed, order: 10) { format_duration(Time.now - start_at) }
shell.info(:tokens,  order: 20) { "↓ #{counter.human}" }
```

- `order` 未指定は登録順
- 戻り値が `nil` または空文字 → そのセグメントは描画スキップ
- 60ms tick で全 block 評価される。dRuby 越しになるため負荷注意。将来 `cache:` hint 追加検討。

### 6.5 slash command

#### parsing

- 入力行が `/` で始まる → slash として扱う
- shellwords 相当でスペース区切り、ダブルクォート対応
- 名前は `[a-z][a-z0-9_-]*` のみ許容、それ以外は warn ログ

#### dispatch

```ruby
shell.slash(:reset) do |args, ctx|
  ctx.state.clear
  ctx.display.append("session reset", style: :result)
end

shell.slash(:quit) { |_, ctx| ctx.quit }
```

- 戻り値は無視（display は明示的に push）
- 未登録 slash → F が error スタイルで表示 + warn ログ
- **組み込み slash は無し**（Minimal Core）

#### slash 名補完

入力が `/` で始まりコマンド名未完成 → F が登録済 slash 名一覧を直接返す（impl の `on_tab` を呼ばない）。引数部分の補完は impl の `on_tab` に渡る。

## 7. State / Error handling / Ruby::Box

### 7.1 state store

#### 性質

- F の Main R が保持する shared key-value
- key は Symbol 推奨、value は Ractor.shareable（frozen primitive 等）
- 変化時 `on_state_change` 発火

#### tuple 表現

```
[:state, key, value]
```

書き換えは「旧値 take → 新値 write → `[:event, :state_change, key, old, new]` write」のシーケンス。

#### 外部 injection

別プロセスから dRuby 経由で同じ tuple 空間に書き込めば反映。Slack adapter 等は dRuby client として書く。

```ruby
# 外部から
ts = DRbObject.new_with_uri('drbunix:///tmp/cclikesh-XXX.sock')
ts.write([:state, :phase, :paused])
```

### 7.2 error handling

| 発生場所 | F の対応 |
|---|---|
| impl callback で例外 | rescue → error ログ → display に error style → loop 継続 |
| before_*/after_* で例外 | rescue → error ログ → 当該 hook chain 中断 → main 処理続行 |
| F 内部 Ractor で例外 | F 全体クラッシュ扱い、shutdown sequence 起動 |
| dRuby 接続切断 | F は warn ログ → on_quit 発火 → terminate |
| reline 例外 | rescue → 入力欄 reset → continue |

例外は握り潰さず必ず logger に流す。crash recovery は MVP では行わない。

### 7.3 Ruby::Box 境界（最終）

dRuby + Ractor で impl-F が物理分離した結果、Box の役割は F-internal の防御に限定。

- **Box 内**: reline、irb（F が選択 require 時）、カーソル制御 ANSI、reline が触る `String`/`IO` 拡張
- **Box 外**: ts4r、DRb、Ractor 構築コード、logger、env

```ruby
# F の起動初期 (Box 外)
require 'ts4r'
require 'drb/drb'

# Box 作って中で reline 等 require
internal = Ruby::Box.new
internal.require 'reline'
# 外側からアクセス: internal::Reline
```

Box 内 require の汚染（例: reline の `String#each_grapheme_cluster` 拡張）は Box 内に閉じる。

### 7.4 標準 logger

- 出力先デフォルト `$stderr`、level デフォルト `:info`、progname `"cclikesh"`
- format は Ruby Logger デフォルトそのまま
- F が標準で記録するイベント
  - info: shell start/quit, slash dispatched, state change
  - debug: on_submit/on_tab fired, before/after hook, live slot lifecycle, spinner frame
  - warn: 不明な slash, state injection name 衝突
  - error: callback 内 unhandled exception (stack trace 付)

## 8. Example impl: irb-claude-code-style

### 8.1 ディレクトリ構成

```
cclikesh/
├── lib/cclikesh/...
├── examples/
│   └── irb_shell/
│       ├── irb_shell.rb
│       ├── irb_evaluator.rb
│       ├── irb_completer.rb
│       └── byte_counter.rb
└── ...
```

### 8.2 entry point

```ruby
require 'cclikesh'
require_relative 'irb_evaluator'
require_relative 'irb_completer'
require_relative 'byte_counter'

evaluator = IrbEvaluator.new
completer = IrbCompleter.new(evaluator.binding)
counter   = ByteCounter.new
start_at  = Time.now

Cclikesh.run do |shell|
  shell.on_submit do |line, ctx|
    ctx.display.append(line, prompt: "irb(main)> ")
    counter.add(line.bytesize)

    ctx.state[:phase] = :working
    slot = ctx.display.open_live(style: :thinking)

    begin
      result = evaluator.evaluate(line)
      slot.commit
      ctx.display.append("=> #{result.inspect}", style: :result)
      counter.add(result.inspect.bytesize)
    rescue ScriptError, StandardError => e
      slot.discard
      ctx.display.append("#{e.class}: #{e.message}", style: :error)
      ctx.logger.error(e.full_message)
    ensure
      ctx.state[:phase] = :idle
    end
  end

  shell.on_tab do |buf, pos, ctx|
    candidates = completer.candidates(buf, pos)
    ctx.dialog.show(candidates.join("\n")) if candidates.size > 1
    candidates
  end

  shell.info(:elapsed, order: 10) { format_duration(Time.now - start_at) }
  shell.info(:tokens,  order: 20) { "↓ #{counter.human}" }

  shell.spinner_label do
    ctx.state[:phase] == :working ? :auto : nil
  end

  shell.slash(:reset) do |_args, ctx|
    evaluator.reset
    counter.reset
    ctx.display.append("session reset", style: :result)
  end

  shell.slash(:quit) { |_, ctx| ctx.quit }
  shell.slash(:q)    { |_, ctx| ctx.quit }
end

def format_duration(sec)
  m, s = sec.divmod(60)
  m.zero? ? "#{s.to_i}s" : "#{m.to_i}m #{s.to_i}s"
end
```

40 行ちょい。impl 全体 pure Ruby で、F-API 接合は `shell.*` と `ctx.*` のみ。

## 9. Testing 戦略

### 9.1 F 本体

- `test-unit` gem（`~/dev/src/CLAUDE.md` 規約）
- `Rakefile` で `rake test`
- ts4r tuple 操作はモックせず実 ts4r 使用
- Render R / Input R は実起動せず、tuple inject + read で挙動確認
- reline はテストでは bypass、dummy IO でキー event tuple 直接 inject

例:
```ruby
class TestDispatcher < Test::Unit::TestCase
  def test_enter_emits_submit_event
    ts = TupleSpace4Ractor.new
    Cclikesh::Dispatcher.start(ts)
    ts.write([:key, "h"])
    ts.write([:key, "i"])
    ts.write([:key, "\n"])
    _, _, line = ts.take([:event, :submit, nil])
    assert_equal "hi", line
  end
end
```

### 9.2 example impl

`Cclikesh.run` を起動せず impl の純粋クラス（`IrbEvaluator` 等）だけテスト。Cclikesh 接合面は手動確認。

### 9.3 CI

- GitHub Actions、Ruby 4.0.3、`bundle exec rake test`
- Ractor + dRuby 系は flake 可能性あり、retry 1 回入れて様子見

### 9.4 TDD コミット境界

- RED: failing spec → commit
- GREEN: 最小実装 → commit
- REFACTOR: 必要時のみ commit

## 10. 依存・gem 名

### 10.1 gemspec

```ruby
spec.required_ruby_version = ">= 4.0.0"
spec.add_runtime_dependency "reline", "~> 0.5"
spec.add_runtime_dependency "ts4r"

spec.add_development_dependency "test-unit"
spec.add_development_dependency "rake"
```

ts4r が rubygems 未公開の場合 Gemfile で git source 指定:
```ruby
gem "ts4r", git: "https://github.com/seki/ts4r.git", branch: "main"
```

irb は F は依存しない。example impl 側で `require 'irb/completion'`。

### 10.2 命名

- gem 名: `cclikesh`
- top-level module: `Cclikesh`
- 内部 TupleSpace: `Cclikesh::TupleSpace`
- DSL エントリ: `Cclikesh.run do |shell| ... end`

## 11. 明示的にやらないこと

- middleware パイプライン
- session 永続化 / replay / crash recovery
- 1 プロセスに複数 shell 並走
- syntax highlighter 内蔵
- 補完候補 source の標準提供
- 組み込み slash command
- async/await 抽象（Thread/Fiber/Ractor で十分）
- Python / 他言語サポート

## 12. 将来検討

- `cclikesh/extras` 層（spinner プリセット集、info segment ヘルパー、組み込み slash 等）
- info segment の cache hint
- crash recovery（auto restart）
- ts4r `break/continue` を活用した「中断 → 外部介入 → 再開」プリミティブ
