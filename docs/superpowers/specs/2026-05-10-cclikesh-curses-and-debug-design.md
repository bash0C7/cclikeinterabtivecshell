# cclikesh 全面再設計: curses 移行 + Ractor 並行 + debug 基盤

## Goal

cclikesh framework を未リリースの利を活かして全体最適に再設計する。柱は 3 本:

1. **描画基盤を curses (ncursesw) に全面移行**: 自前 ANSI emit / DECSTBM / alt-screen 管理コードを破棄、ncurses の枯れたロジックに乗る。CJK / wide-char は curses + `unicode-display_width` gem 任せ。
2. **multi-process + DRb の構造を解体**: 単一プロセス化、UI と handler は Ractor で安全並列。thread を直接扱わない。
3. **debug 基盤 `cclikesh-debug` を sub-gem として新設**: Claude Code が CLI で input / capture / extract できる per-session SQLite 記録 + sqlite-vec semantic 検索 + asciinema cast 経由の動画 export。

副次的な狙い:

- 31 ファイルを ~14 に圧縮、各ファイル ≤200 行を目標、shallow layer
- production 動作中の thread / fork / DRb 0 (debug 起動時のみ DRb opt-in)
- Claude Code 風 UX (handler 走行中も次プロンプトを打てる) を Ractor 並列で実現
- 過去互換性配慮ナシ、examples の手直しは厭わない

## Scope

In:
- 本体 `lib/cclikesh/` の全面書き換え (curses + Ractor + 単一プロセス)
- `examples/echo_shell.rb`, `examples/irb_shell/` の Ractor 適合化
- 既存テスト全件の書き換え (curses 出力期待 + Ractor message flow)
- `cclikesh-debug` sub-gem (`cclikesh-debug/` ディレクトリに gemspec ごと新設)
- `_sqlite_mcp_meta` 経由の chiebukuro-mcp 登録互換性

Out:
- 段階移行 / backward-compat shim
- 旧 ANSI 直書きパスとの併存
- intent grid + actual grid divergence detection (curses 移行で発生源が消えるため不要と判断)
- triple-lane 動画 / 注釈動画 / 純 Ruby PNG renderer
- web viewer
- 多 session 集約 query (per-session DB の merge スクリプトは v2)

## Target environment

- macOS only (Mac 大前提、自家製ライブラリのため)
- Ruby 4.0.3 以上 (Ractor 安定済前提、ENV `RUBY_VERSION` で 4.0+ を確認)
- Homebrew `ncurses 6.6` (`/opt/homebrew/Cellar/ncurses/6.6`) を curses gem build 時にリンク
- ターミナル: iTerm2 / Apple Terminal / tmux 動作確認

## Architecture

### プロセス・並行モデル

```
┌─────────────────────────────────────────────────────────────────┐
│ cclikesh shell プロセス (1 プロセス)                              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │ Main Ractor (UI)                                        │     │
│  │  - Reline + curses を専有 (mutable module state へのア │     │
│  │    クセスは Main Ractor のみ可能、Ruby Ractor 規約)     │     │
│  │  - canonical state (phase, header, footer, info_bar,   │     │
│  │    status_row, popup, transcript counts) を保持          │     │
│  │  - Reline.readline 主ループ                             │     │
│  │  - Reline dialog poll の 1 つを mailbox drain に充てる、 │     │
│  │    Handler Ractor 等から届いた描画コマンドを実行         │     │
│  └────────────────────────────────────────────────────────┘     │
│       ↑ render commands     ↓ submit / tab events                │
│  ┌────────────────────────────────────────────────────────┐     │
│  │ Handler Ractor (per-invocation, 並行)                    │     │
│  │  Main から spawn、handler 終了で Ractor 死亡             │     │
│  │  ctx は Ractor proxy、ctx.display.append 等は Main へ    │     │
│  │  Ractor.send で命令メッセージを投げる                    │     │
│  └────────────────────────────────────────────────────────┘     │
│       ↕ optional                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │ State Ractor(s) [user opt-in via shareable_ref]          │     │
│  │  evaluator_ref = shell.shareable_ref { IrbEvaluator.new } │    │
│  │  各 mutable user object を専用 Ractor に閉じ込める        │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  Optional (debug 時のみ):                                         │
│  ┌────────────────────────────────────────────────────────┐     │
│  │ Debug DRb thread (ENV[CCLIKESH_DEBUG_SOCK] set 時のみ)  │     │
│  │  Main Ractor の registry を debug daemon に公開          │     │
│  └────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

### debug 系プロセス

```
┌─────────────────────────────────────────────────────────────┐
│ cclikesh-debug daemon プロセス                                │
│ (cclikesh shell の PTY parent + UNIX socket listener)        │
│                                                              │
│ Orchestrator Ractor                                          │
│   ↓ Ractor pipeline:                                         │
│ PTYReader Ractor   - PTY master 読込、bytes chunk を送出     │
│   ↓ [:bytes, chunk, ts]                                      │
│ FrameBuilder Ractor - DRb pull で framework_state、frame 構築│
│   ↓ [:frame, data]                                           │
│ Storage Ractor    - SQLite frame INSERT、DB connection 専有  │
│   ↓ [:frame_id, id]                                          │
│ Embedder Ractor   - informers で embed、frame_vec INSERT     │
└─────────────────────────────────────────────────────────────┘
       ↑ DRb (control, debug_snapshot, debug_drain_events)
       ↓
[shell プロセス]

[Claude Code Bash tool]
       ↓ control
[cclikesh-debug CLI (Driver / Viewer subcommands)]
       ↓ UNIX socket          ↓ readonly SQLite
[cclikesh-debug daemon]   [SQLite per session]
```

### 描画スタック

- `curses` gem (ruby/curses, 前田さん maintainer) を `~> 1.4` で依存
- 起動時に Homebrew ncurses にリンクしてビルド (PATH に `/opt/homebrew/opt/ncurses` を入れて bundle config)
- `Curses.init_screen + Curses.cbreak + Curses.noecho + Curses.start_color + Curses.use_default_colors`
- 各機能 region は固有 `Curses::Window`:
  - `header_win` (高さ 3, 上端)
  - `display_pad` (`Curses::Pad`, 仮想高さ無制限のスクロール領域)
  - `footer_win` (高さ 3, 下端)
  - 入力行 (Reline 専有、curses は paint しない 1 行)
- 描画は per-region `wnoutrefresh`、最後に `Curses.doupdate` 1 回で batched paint
- WINCH は `Curses::KEY_RESIZE` 受信で各 window `wresize` + 再 paint

### CJK / wide-char

- 描画: `window.addstr("日本語")` を ncursesw に丸投げ、cell 進行は ncurses が正しく処理
- レイアウト計算 (折返し、切り詰め、揃え): `Unicode::DisplayWidth.of(s, ambiguous_width)` で計算 (textbringer と同型)
- 内部に wcwidth 系の自前実装は持たない

## 本体 lib/cclikesh/ 構成

14 ファイル、ALL ≤200 行を目標:

```
lib/cclikesh/
├── builder.rb              # DSL (interface 不変、内部に shareable_ref 追加)
├── runner.rb               # Cclikesh.run { }: curses init → Main Ractor loop → teardown
├── chrome.rb               # header_win + footer_win + info_bar + input_box decoration の paint
├── display.rb              # display_pad + append + open_live + dialog (live_slot, dialog box 統合)
├── style.rb                # curses color_pair / attr マッピング (Style.define, Style.with(window, name) { ... })
├── reline_dialogs.rb       # slash menu + ghost text + periodic_tick の 3 本
├── slash_dispatcher.rb     # Main Ractor: submit 受領 → /パース → Handler Ractor spawn
├── slash_registry.rb       # 登録された handler body を make_shareable した形で保持
├── handler_ractor.rb       # Handler Ractor のテンプレート、spawn / monitor / cleanup
├── ctx_proxy.rb            # Handler Ractor 内で使う ctx proxy (display, state, logger 等は Main 宛 message)
├── shareable_ref.rb        # State Ractor 起動 + proxy 提供 (shell.shareable_ref { mutable_obj })
├── context.rb              # Main Ractor 内の真の Context、UI 系 method を直接実装
├── transcript.rb           # Main Ractor 専有の transcript buffer (output 履歴)
├── debug_endpoint.rb       # OPTIONAL: ENV[CCLIKESH_DEBUG_SOCK] set 時のみ DRb 起動
└── version.rb
```

旧構成 (31 ファイル) からの削除対象:

| 削除 | 理由 |
|------|------|
| `dispatcher.rb`, `endpoint.rb`, `forking.rb`, `event_thread.rb`, `tuple_space.rb`, `drb_patches.rb` | impl ↔ F process 分離 + DRb の解体 |
| `screen.rb`, `layout.rb`, `mouse.rb` | curses が代替 (alt-screen, scroll region, mouse は curses 標準) |
| `header.rb`, `footer.rb`, `info_bar.rb`, `input_box.rb` | `chrome.rb` に統合 |
| `live_slot.rb`, `dialog.rb` | `display.rb` に統合 |
| `state.rb` | `context.rb` に統合 |
| `render_thread.rb`, `renderer.rb`, `input_thread.rb` | Main Ractor 内で直接実装、別ファイル不要 |
| `history.rb` | Reline の組み込み history で十分 |
| `handler_registry.rb` | `slash_registry.rb` にリネーム + 簡素化 |

### style.rb (curses attribute table)

```ruby
require 'curses'

module Cclikesh::Style
  # 起動時に init_pair で固定割当
  BUILTIN = {
    result:   { fg: Curses::COLOR_GREEN  },
    error:    { fg: Curses::COLOR_RED    },
    thinking: { fg: Curses::COLOR_MAGENTA },
    dim:      { attr: Curses::A_DIM      },
    gray:     { attr: Curses::A_DIM      },
  }.freeze

  @custom = {}

  def self.init!
    @pair_id = 0
    BUILTIN.each_key { |name| ensure_pair(name) }
    Ractor.make_shareable(@registry = build_registry)
  end

  def self.define(name, fg: nil, bg: nil, bold: false, dim: false, italic: false, underline: false, reverse: false)
    @custom[name] = { fg: fg, bg: bg, bold: bold, dim: dim, italic: italic, underline: underline, reverse: reverse }
    ensure_pair(name)
  end

  def self.with(window, name)
    pair, attrs = lookup(name)
    return yield unless pair
    composed = pair | attrs
    window.attron(composed)
    yield
  ensure
    window.attroff(composed) if composed
  end

  # ... lookup, ensure_pair (init_pair to map name → curses color_pair id)
end
```

ANSI 文字列を生成するコードは一切持たない。

### chrome.rb (header / footer / info_bar / input_box decoration)

```ruby
module Cclikesh::Chrome
  HEADER_HEIGHT = 3
  FOOTER_HEIGHT = 3

  def self.init(builder)
    @header = Curses::Window.new(HEADER_HEIGHT, Curses.cols, 0, 0)
    @footer = Curses::Window.new(FOOTER_HEIGHT, Curses.cols,
                                  Curses.lines - FOOTER_HEIGHT - 1, 0)
    # 入力行 = Curses.lines - 1 (1 行確保) → curses window 作らない (Reline 占有)
  end

  def self.update_header(lines)
    @header.clear
    lines.each_with_index do |line, i|
      @header.setpos(i, 0)
      @header.addstr(truncate(line, Curses.cols - 2))
    end
    @header.noutrefresh
  end

  def self.update_footer(info_bar_items, status_rows, shortcuts_hint)
    # Footer 段組計算は Unicode::DisplayWidth で
    @footer.clear
    # ... addstr per line
    @footer.noutrefresh
  end

  def self.tick_spinner(phase, label)
    return unless phase == :working
    # spinner phase を 1 step 進めて footer の左端 cell に書く
    @footer.setpos(0, 0)
    @footer.addstr(spinner_glyph(@spinner_phase))
    @spinner_phase = (@spinner_phase + 1) % 10
    @footer.noutrefresh
  end

  def self.handle_resize
    Curses.refresh  # ← KEY_RESIZE 受け取り後
    @header.resize(HEADER_HEIGHT, Curses.cols)
    @footer.resize(FOOTER_HEIGHT, Curses.cols)
    @footer.move(Curses.lines - FOOTER_HEIGHT - 1, 0)
    update_header(@last_header_lines || [])
    update_footer(@last_info_bar || [], @last_status_rows || [], @last_hint || "")
  end

  # ... truncate, spinner_glyph
end
```

### display.rb (display_pad + live_slot + dialog box)

```ruby
module Cclikesh::Display
  PAD_HEIGHT = 10_000  # 仮想スクロール、scroll back 用

  def self.init
    @pad = Curses::Pad.new(PAD_HEIGHT, Curses.cols)
    @pad.scrollok(true)
    @row = 0
    @live_slots = {}  # sid → { row:, last_text: }
    @next_sid = 0
  end

  def self.append(text, prompt: nil, style: nil)
    rendered = (prompt || "") + text
    @pad.setpos(@row, 0)
    Cclikesh::Style.with(@pad, style) do
      @pad.addstr(rendered)
    end
    @row += 1
    refresh
    Cclikesh::Transcript.record(rendered)
  end

  def self.open_live(style: nil)
    sid = (@next_sid += 1)
    @live_slots[sid] = { row: @row, last_text: "", style: style }
    @row += 1
    sid
  end

  def self.live_update(sid, text)
    slot = @live_slots[sid] or return
    @pad.setpos(slot[:row], 0)
    @pad.clrtoeol
    Cclikesh::Style.with(@pad, slot[:style]) do
      @pad.addstr(text)
    end
    slot[:last_text] = text
    refresh
  end

  def self.live_commit(sid, final_text = nil)
    slot = @live_slots.delete(sid) or return
    final = final_text || slot[:last_text]
    @pad.setpos(slot[:row], 0)
    @pad.clrtoeol
    Cclikesh::Style.with(@pad, slot[:style]) { @pad.addstr(final) }
    Cclikesh::Transcript.record(final)
    refresh
  end

  def self.live_discard(sid)
    slot = @live_slots.delete(sid) or return
    @pad.setpos(slot[:row], 0)
    @pad.clrtoeol
    @row -= 1 if slot[:row] == @row - 1  # 末尾だけ巻き戻し
    refresh
  end

  def self.dialog(content, style: nil)
    lines = content.to_s.split("\n", -1)
    lines.pop if lines.last == ""
    width = (lines.map { |l| Unicode::DisplayWidth.of(l) }.max || 0) + 2
    append("┌#{"─" * width}┐", style: :dim)
    lines.each { |line| append("│ #{line.ljust(width - 2)} │", style: style) }
    append("└#{"─" * width}┘", style: :dim)
  end

  private

  def self.refresh
    visible_top = [@row - (Curses.lines - Cclikesh::Chrome::HEADER_HEIGHT - Cclikesh::Chrome::FOOTER_HEIGHT - 2), 0].max
    @pad.pnoutrefresh(visible_top, 0,
                       Cclikesh::Chrome::HEADER_HEIGHT, 0,
                       Curses.lines - Cclikesh::Chrome::FOOTER_HEIGHT - 2, Curses.cols - 1)
  end
end
```

### Main Ractor loop (runner.rb)

```ruby
module Cclikesh::Runner
  def self.run(builder)
    init_curses!
    Cclikesh::Style.init!
    Cclikesh::Chrome.init(builder)
    Cclikesh::Display.init
    Cclikesh::DebugEndpoint.start_if_enabled(builder)
    Cclikesh::RelineDialogs.install(builder)

    ctx = Cclikesh::Context.new(builder)
    builder.on_start_handlers.each { |h| h.call(ctx) }

    catch(:quit) do
      loop do
        line = Reline.readline(prompt_string(ctx), true)
        throw :quit if line.nil?  # EOF
        Cclikesh::SlashDispatcher.handle(line, builder)
        # ↑ 内部で Handler Ractor を spawn、結果は mailbox に流れる
        # readline ループに即戻る → 並行で handler 走る
        # dialog poll が mailbox を drain してくれる
      end
    end

    builder.on_quit_handlers.each { |h| h.call(ctx) }
  ensure
    teardown_curses!
  end

  private

  def self.init_curses!
    Curses.init_screen
    Curses.cbreak
    Curses.noecho
    Curses.start_color
    Curses.use_default_colors
    Curses.stdscr.keypad(true)  # KEY_RESIZE 受け取りに必要
  end

  def self.teardown_curses!
    Curses.close_screen
  end
end
```

### Reline dialog poll で mailbox drain

```ruby
module Cclikesh::RelineDialogs
  def self.install(builder)
    Reline.add_dialog_proc(:periodic_tick, proc do
      drain_main_mailbox
      Cclikesh::Chrome.update_footer_clock if needs_clock_update?
      Cclikesh::Chrome.tick_spinner(current_phase, current_spinner_label)
      Curses.doupdate
      nil  # Reline には何も popup させへん
    end, Reline::DEFAULT_DIALOG_CONTEXT)

    # ... 既存 slash_menu_dialog, ghost_text_dialog
  end

  def self.drain_main_mailbox
    100.times do  # 1 tick で最大 100 メッセージまで処理
      msg = Ractor.current.receive_if(timeout: 0) { true }
      break unless msg
      apply_command(msg)
    end
  rescue Ractor::Error
    nil
  end

  def self.apply_command(msg)
    case msg
    in [:append, text, opts]
      Cclikesh::Display.append(text, **opts)
    in [:open_live, sid, opts]
      Cclikesh::Display.open_live(**opts)  # sid は handler 側に応答
    in [:live_update, sid, text]
      Cclikesh::Display.live_update(sid, text)
    in [:live_commit, sid, final]
      Cclikesh::Display.live_commit(sid, final)
    in [:live_discard, sid]
      Cclikesh::Display.live_discard(sid)
    in [:dialog, content, opts]
      Cclikesh::Display.dialog(content, **opts)
    in [:state_set, key, value]
      Cclikesh::Context.state_set(key, value)
    in [:logger, level, msg_text]
      Cclikesh::Context.logger.send(level, msg_text)
    end
  end
end
```

### Handler Ractor spawn

```ruby
module Cclikesh::SlashDispatcher
  def self.handle(line, builder)
    if line.start_with?("/")
      name, *args = line[1..].split
      handler = builder.slash_handlers[name.to_sym]
      return Cclikesh::Display.append("Unknown command: /#{name}", style: :error) unless handler
      spawn_handler_ractor(handler, args, builder)
    else
      handler = builder.on_submit_handler
      spawn_handler_ractor(handler, [line], builder, mode: :submit)
    end
  end

  def self.spawn_handler_ractor(handler_body, args, builder, mode: :slash)
    main = Ractor.current
    state_refs = builder.shareable_refs  # name → Ractor handle (frozen Hash)
    ctx_proxy_blueprint = Cclikesh::CtxProxy.blueprint(main, state_refs)
    args_frozen = args.map(&:freeze).freeze

    Ractor.new(handler_body, args_frozen, ctx_proxy_blueprint) do |body, a, ctx_blueprint|
      ctx = Cclikesh::CtxProxy.from_blueprint(ctx_blueprint)
      begin
        body.call(*a, ctx)
      rescue => e
        ctx.display.append("#{e.class}: #{e.message}", style: :error)
        ctx.logger.error(e.full_message)
      end
    end
    # 戻り値の Ractor handle は捨てる、handler は自走、終わったら勝手に死ぬ
  end
end
```

### Ctx proxy

```ruby
class Cclikesh::CtxProxy
  Blueprint = Struct.new(:main_ractor, :state_refs, keyword_init: true) do
    def freeze; super end
  end

  def self.blueprint(main, state_refs)
    Ractor.make_shareable(Blueprint.new(main_ractor: main, state_refs: state_refs))
  end

  def self.from_blueprint(bp)
    new(bp.main_ractor, bp.state_refs)
  end

  def initialize(main, state_refs)
    @main = main; @state_refs = state_refs
    @display = DisplayProxy.new(@main)
    @logger  = LoggerProxy.new(@main)
    @state   = StateProxy.new(@main)
  end

  attr_reader :display, :logger, :state

  def shareable(name)
    @state_refs[name]
  end

  def quit
    @main.send([:quit])
  end
end

class Cclikesh::CtxProxy::DisplayProxy
  def initialize(main); @main = main; end

  def append(text, prompt: nil, style: nil)
    @main.send([:append, text, { prompt: prompt, style: style }.compact])
  end

  def open_live(style: nil, &block)
    sid = request_open_live(style)
    slot = LiveSlot.new(@main, sid)
    if block
      begin
        block.call(slot)
        slot.commit unless slot.committed?
      rescue
        slot.discard
        raise
      end
    end
    slot
  end

  def dialog(content, style: nil)
    @main.send([:dialog, content, { style: style }.compact])
  end

  private

  def request_open_live(style)
    me = Ractor.current
    @main.send([:open_live_request, me, { style: style }.compact])
    msg = Ractor.current.receive_if { |m| m.is_a?(Array) && m[0] == :open_live_reply }
    msg[1]  # sid
  end
end
```

Main Ractor 側 dialog proc は `[:open_live_request, reply_to, opts]` を受領したら `Cclikesh::Display.open_live(**opts)` で sid を確定 → `reply_to.send([:open_live_reply, sid])`。同期的 RPC が 1 往復で完結。`socket_protocol.rb` ではなく Ractor mailbox で完結 (process 内通信なので socket は debug 時だけ)。

## DSL 変更点 (examples 影響)

### echo_shell.rb (微小)

`start_at = Time.now` の Time は frozen / shareable、現状 OK。`shell.btw`, `shell.on_submit`, `shell.slash` の各 block は closure 捕捉が Time / String / Integer のみなら `Ractor.make_shareable` で自動移行可。

### irb_shell.rb (中程度の修正)

mutable な `IrbEvaluator`, `ByteCounter`, `IrbCompleter` を `shell.shareable_ref { ... }` 経由に書き換え:

```ruby
# Before:
evaluator = IrbEvaluator.new
counter   = ByteCounter.new
completer = IrbCompleter.new(evaluator.binding)

shell.on_submit do |line, ctx|
  result = evaluator.evaluate(line)
  counter.add(line.bytesize)
  ...
end

# After:
evaluator_ref = shell.shareable_ref(:evaluator) { IrbEvaluator.new }
counter_ref   = shell.shareable_ref(:counter)   { ByteCounter.new }
completer_ref = shell.shareable_ref(:completer) { IrbCompleter.new }

shell.on_submit do |line, ctx|
  ctx.display.append(line, prompt: "irb(main)> ")
  ctx.shareable(:counter).call(:add, line.bytesize)
  ctx.state[:phase] = :working
  slot = ctx.display.open_live(style: :thinking)
  slot.update("evaluating...")
  begin
    result = ctx.shareable(:evaluator).call(:evaluate, line)
    slot.commit
    ctx.display.append("=> #{result.inspect}", style: :result)
    ctx.shareable(:counter).call(:add, result.inspect.bytesize)
  rescue ScriptError, StandardError => e
    slot.discard
    ctx.display.append("#{e.class}: #{e.message}", style: :error)
    ctx.logger.error(e.full_message)
  ensure
    ctx.state[:phase] = :idle
  end
end
```

### `ctx.dialog.show` → `ctx.display.dialog`

```ruby
# Before
ctx.dialog.show(args.join(" "), style: :result)

# After
ctx.display.dialog(args.join(" "), style: :result)
```

`ctx.dialog` API は廃止。examples 2 箇所修正。

### ShareableRef API

```ruby
class Cclikesh::ShareableRef
  def self.spawn(name, &block)
    object = block.call  # Builder context で呼ぶ、まだ Ractor じゃない
    ractor = Ractor.new(object) do |obj|
      loop do
        msg = receive
        break if msg == :stop
        method, *args = msg
        result = obj.public_send(method, *args)
        Ractor.yield(result)
      end
    end
    new(name, ractor)
  end

  def initialize(name, ractor)
    @name, @ractor = name, ractor
  end

  def call(method, *args)
    @ractor.send([method, *args.map(&:freeze).freeze])
    @ractor.take
  end

  def stop
    @ractor.send(:stop)
  end
end
```

# debug 基盤 (cclikesh-debug sub-gem)

## ディレクトリ layout

```
cclikeinterabtivecshell/
├── cclikesh.gemspec                            ← 本体 gem
├── lib/cclikesh/...                            ← 上記
├── cclikesh-debug/                             ← sub-gem ディレクトリ
│   ├── cclikesh-debug.gemspec
│   ├── exe/cclikesh-debug                      ← CLI entrypoint
│   ├── lib/cclikesh/debug/
│   │   ├── recorder.rb                         # orchestrator Ractor
│   │   ├── ractors/
│   │   │   ├── pty_reader.rb                   # PTY tap → bytes 送出
│   │   │   ├── frame_builder.rb                # DRb pull + frame 構築
│   │   │   ├── storage_writer.rb               # SQLite frame INSERT
│   │   │   └── embedder.rb                     # informers + frame_vec INSERT
│   │   ├── driver/                             # CLI 操作系 subcommand
│   │   │   ├── start.rb
│   │   │   ├── input.rb
│   │   │   ├── capture.rb
│   │   │   ├── wait.rb
│   │   │   ├── stop.rb
│   │   │   └── tail.rb
│   │   ├── viewer/                             # CLI 閲覧系 subcommand
│   │   │   ├── list.rb
│   │   │   ├── info.rb
│   │   │   ├── frames.rb
│   │   │   ├── grid.rb
│   │   │   ├── query.rb
│   │   │   ├── semantic.rb
│   │   │   ├── export.rb
│   │   │   └── clean.rb
│   │   ├── storage.rb                          # SQLite open / schema / insert / select
│   │   ├── socket_protocol.rb                  # JSON-line over UNIX socket
│   │   ├── embedder_pool.rb                    # informers ラッパー (ruri-v3-310m-onnx)
│   │   ├── content_builder.rb                  # framework_state → embed 用 content text
│   │   ├── cast_writer.rb                      # asciinema v2 JSON-lines emit
│   │   ├── meta_seeds.rb                       # _sqlite_mcp_meta 初期 INSERT (chiebukuro 互換)
│   │   └── version.rb
│   └── test/cclikesh-debug/...
└── ...
```

## sub-gem 依存

```ruby
# cclikesh-debug.gemspec
Gem::Specification.new do |s|
  s.name    = 'cclikesh-debug'
  s.version = Cclikesh::Debug::VERSION
  s.required_ruby_version = '>= 4.0.0'
  s.add_dependency 'cclikesh',                  '>= 0.2'  # debug_snapshot 提供版
  s.add_dependency 'sqlite3',                   '~> 2.0'
  s.add_dependency 'sqlite-vec',                '~> 0.1'
  s.add_dependency 'informers',                 '~> 1.2'
end
```

本体 cclikesh.gemspec は `curses ~> 1.4`, `reline ~> 0.5`, `unicode-display_width ~> 3.0`, `logger`, `rinda ~> 0.2` (DRb 起動用、debug 時だけ DRb start)。

## 本体への侵襲点

`lib/cclikesh/debug_endpoint.rb` (新規 1 ファイル) で外部公開:

```ruby
module Cclikesh::DebugEndpoint
  def self.start_if_enabled(builder)
    sock = ENV['CCLIKESH_DEBUG_SOCK']
    return unless sock
    require 'drb/drb'
    @adapter = Adapter.new(builder)
    DRb.start_service("drbunix:#{sock}.drb", @adapter)
  end

  class Adapter
    include DRb::DRbUndumped

    def initialize(builder); @builder = builder; @event_queue = []; @mutex = Mutex.new; end

    def debug_snapshot
      @mutex.synchronize do
        {
          framework_state: build_framework_state_hash,
          cursor:          [Curses.stdscr.cury, Curses.stdscr.curx],
          ts_shell:        Process.clock_gettime(Process::CLOCK_MONOTONIC),
        }
      end
    end

    def debug_drain_events
      @mutex.synchronize { e = @event_queue.dup; @event_queue.clear; e }
    end

    def push_event(kind, payload = {})
      @mutex.synchronize { @event_queue << { kind: kind, payload: payload, ts: Time.now.to_f } }
    end

    private

    def build_framework_state_hash
      {
        phase:             Cclikesh::Context.state[:phase],
        focus_mode:        Cclikesh::Context.state[:focus_mode],
        header:            @builder.header_config_hash,
        info_bar:          @builder.evaluate_info_bar,
        status_rows:       @builder.evaluate_status_rows,
        spinner_label:     @builder.evaluate_spinner_label,
        prompt_suggestion: @builder.evaluate_prompt_suggestion,
        shortcuts_hint:    @builder.shortcuts_hint_text,
        input:             { buffer: Reline.line_buffer, cursor_pos: Reline.point },
        live_slot:         Cclikesh::Display.live_slot_state,
        popup:             Cclikesh::RelineDialogs.popup_state,
        transcript_line_count: Cclikesh::Transcript.lines.size,
      }
    end
  end
end
```

加えて、本体の event 発火点で `Cclikesh::DebugEndpoint.adapter&.push_event(...)` を 1 行ずつ:

- `runner.rb` の Reline submit 後: `push_event(:input_received, line: line)`
- `chrome.rb` の `tick_spinner` 後: `push_event(:render_commit)` (cadence で間引く)
- state mutation 時: `push_event(:state_change, key:, from:, to:)`

production (env var 無し) では `@adapter` は nil、push_event は no-op、本体は自前 thread / fork ゼロ。

## SQLite schema (per-session、chiebukuro-mcp 互換)

```sql
CREATE TABLE session_info(
  uuid         TEXT PRIMARY KEY,
  started_at   TEXT NOT NULL,        -- ISO8601
  ended_at     TEXT,
  shell_argv   TEXT NOT NULL,        -- JSON array
  cclikesh_ver TEXT NOT NULL,
  rows         INTEGER NOT NULL,
  cols         INTEGER NOT NULL,
  embedder     TEXT NOT NULL,
  notes        TEXT
);

CREATE TABLE frames(
  id                   INTEGER PRIMARY KEY,
  ts                   REAL    NOT NULL,    -- session 開始からの monotonic 秒
  trigger              TEXT    NOT NULL,    -- 'periodic' | 'event' | 'on_demand'
  event_kind           TEXT,                -- nullable: 'input_received' 等
  cursor_row           INTEGER NOT NULL,
  cursor_col           INTEGER NOT NULL,
  raw_bytes_zlib       BLOB,                -- 前 frame からの PTY 差分、zlib 圧縮、再生用
  framework_state_json TEXT    NOT NULL,    -- DRb pull 結果の JSON
  content              TEXT    NOT NULL,    -- chiebukuro-mcp 互換 column 名、framework_state から build
  source               TEXT    NOT NULL DEFAULT 'framework_state'  -- chiebukuro-mcp 互換
);

CREATE INDEX idx_frames_ts          ON frames(ts);
CREATE INDEX idx_frames_event_kind  ON frames(event_kind) WHERE event_kind IS NOT NULL;

-- vector 検索 (sqlite-vec)
CREATE VIRTUAL TABLE frame_vec USING vec0(
  frame_id   INTEGER PRIMARY KEY,
  embedding  FLOAT[768]
);

-- chiebukuro-mcp 自己記述
CREATE TABLE _sqlite_mcp_meta(
  object_type   TEXT,
  object_name   TEXT,
  description   TEXT,
  hints_json    TEXT,
  recipe_sql    TEXT,
  recipe_label  TEXT,
  PRIMARY KEY (object_type, object_name)
);
```

`_sqlite_mcp_meta` 初期 INSERT (`meta_seeds.rb` から template):

| object_type | object_name | description / recipe_sql |
|------------|------------|--------------------------|
| `db` | `cclikesh_debug` | `cclikesh debug session — frame log + sqlite-vec semantic search` |
| `table` | `frames` | `one row per captured frame` |
| `column` | `frames.content` | `visible / framework state derived text, embed target` |
| `column` | `frames.event_kind` | `nullable; tags event-driven frames` |
| `recipe` | `popup_active` | `SELECT id, ts FROM frames WHERE json_extract(framework_state_json,'$.popup.active')=1 ORDER BY ts` (label: `frames with popup active`) |
| `recipe` | `latest` | `SELECT id, ts, event_kind, content FROM frames ORDER BY ts DESC LIMIT 50` (label: `latest 50 frames`) |
| `recipe` | `phase_working` | `SELECT id, ts, content FROM frames WHERE json_extract(framework_state_json,'$.phase')='working' ORDER BY ts` (label: `frames during :working phase`) |

DB 配置: `tmp/cclikesh-debug/<YYYY-MM-DD-HHMMSS>-<pid>-<short_uuid>.sqlite` (default、ENV `CCLIKESH_DEBUG_DIR` で上書き可)。WAL mode。

## CLI surface

```
cclikesh-debug start <example.rb>
  [--cadence-ms=50]
  [--rows=24] [--cols=80]                  # default = 現 terminal
  [--no-vector]                            # frame_vec 埋め込みスキップ
  [--embed-after-stop]                     # session 中は queue、stop 時に bulk embed
  [--note="..."]
  [--out-dir=<path>]
→ stdout に session_uuid と DB path

cclikesh-debug list                        # 動作中 session + 終了済 file 一覧
cclikesh-debug stop <session>              # 上品な shutdown、最後の frame 取り
cclikesh-debug input <session> "<keys>"    # \r \t \e[A 等エスケープ展開、--raw でそのまま
cclikesh-debug capture <session>           # 強制 1 frame
cclikesh-debug wait <session> --idle <ms>  # actual byte stream 静止 N ms 待ち
cclikesh-debug tail <session>              # 新着 frame 表示

cclikesh-debug frames <session>
  [--since <ts>] [--until <ts>]
  [--event-kind <name>]
  [--popup-active] [--phase <name>]
  [--limit <n>] [--format=tsv|json]

cclikesh-debug grid <session> --frame N
  [--ansi|--plain]                         # raw_bytes_zlib を asciinema 経由で render

cclikesh-debug info <session> [--frame N]  # session_info、frame の framework_state pretty
cclikesh-debug query <session> "<SQL>" [--format=tsv|json]
cclikesh-debug semantic <session> "<query>" [-k 5]

cclikesh-debug export <session>
  --format=cast|gif|mp4|webm
  [--output=<path>]
  [--since <ts>] [--until <ts>]
  [--speed=<n>]
  [--max-idle=<sec>]

cclikesh-debug clean [--older-than 7d]
```

共通規約:
- session 指定: uuid prefix or DB file path、active 1 個なら省略可
- exit code: 0 / 1 user error / 2 not found / 3 daemon unreachable / 4 SQL error
- ENV `CCLIKESH_DEBUG_DIR` で session 置き場上書き

## Recorder Ractor pipeline

```ruby
# lib/cclikesh/debug/recorder.rb
class Cclikesh::Debug::Recorder
  def self.start(opts)
    pty_reader  = Ractor.new(...) { ... }
    frame_build = Ractor.new(pty_reader_handle, drb_uri, ...) { ... }
    storage     = Ractor.new(db_path, ...) { ... }
    embedder    = Ractor.new(...) { ... }

    # 4 個を pipeline 接続:
    #   pty_reader → frame_build (Ractor.send [:bytes, chunk, ts])
    #   frame_build → storage (Ractor.send [:frame, frame_data])
    #   storage → embedder (Ractor.send [:frame_id, id, content])
    #   embedder → storage (Ractor.send [:vec, frame_id, blob])

    orchestrator_loop(pipeline_handles, control_socket)
  end
end
```

各 Ractor は単一責務、メッセージは frozen / shareable のみ通る。`embedder` は Ractor に閉じ込めることで informers の重い ONNX 推論が他 stage を巻き込まへん、true parallelism on multi-core。

## Embedding

- model: `mochiya98/ruri-v3-310m-onnx` (768-dim, 日本語 sentence embedding, normalized)
- gem: `informers ~> 1.2`
- chiebukuro-mcp の `Embedder` パターンをそのまま流用 (`result = @model.(text, model_output: 'sentence_embedding', normalize: true).flatten`)
- SQLite 書込: `embedding.pack('f*')` で BLOB 化、`vec0` virtual table の `MATCH ?` 演算子で検索

## 動画 export

- v1 primary store は SQLite
- `cclikesh-debug export <session> --format=cast` で `.cast` (asciinema v2 JSON-lines) を生成、純 Ruby
- `--format=gif` / `--format=mp4` / `--format=webm` は外部 `agg` + `ffmpeg` を `Open3.popen3` で叩く
- 不在時: stderr に「`brew install agg ffmpeg` で入る」旨明示
- raw bytes は per-frame zlib 圧縮されてるので、export 時に decompress + concat + ts 含めて asciinema 形式に整形

# Test 戦略

## 本体 (cclikesh)

- 既存 ~315 tests を curses + Ractor 移行後に全 pass
- 旧 ANSI escape 期待値 → curses 出力 / window.inch 経由の cell 内容 assert に書き換え
- 新規:
  - `test/test_curses_integration.rb` — Curses.init_screen → Window 作成 → addstr → inch 読出
  - `test/test_japanese_paint.rb` — `addstr("✻ cclikesh — 日本語タイトル")` の cell 進行 / wide_char 折返し
  - `test/test_ractor_handler_dispatch.rb` — handler を make_shareable して Ractor 起動、ctx_proxy 経由で append が Main mailbox に届くこと
  - `test/test_shareable_ref.rb` — IrbEvaluator もどきの mock を State Ractor に格納、proxy 経由で evaluate 呼び出し
  - `test/test_debug_endpoint.rb` — ENV 設定時のみ DRb 起動、debug_snapshot の shape

## sub-gem (cclikesh-debug)

- `test_storage.rb` — SQLite schema / frame insert / `_sqlite_mcp_meta` seed
- `test_content_builder.rb` — framework_state → text の組立、popup_active 時のマーカー
- `test_embedder.rb` — informers モック (固定 768-dim 配列返す stub) で contract test
- `test_cast_writer.rb` — asciinema v2 仕様準拠
- `test_socket_protocol.rb` — JSON command 送受信 round-trip
- `test_recorder_pipeline.rb` — モック PTY + モック DRb 上で 4 Ractor pipeline を 1 cycle 回す
- `test_e2e_full_session.rb` — `cclikesh-debug start examples/echo_shell.rb` → `input` → `capture` → `stop` → SQLite 直 SELECT で frame 数 / framework_state / embedding 検証

# Probe Task 0 (Ractor + curses + Reline 適合性 spike)

実装着手前に **半日 〜 1 日** 投じる probe task:

1. Probe 1: `Reline.readline` を Main Ractor で実行して動作確認 (baseline)
2. Probe 2: `Curses.init_screen + Curses::Window + addstr("日本語")` の正常 render
3. Probe 3: 別 Ractor から `Ractor.send([:append, text])` → Main で `Reline.add_dialog_proc` 経由で受領 + curses paint
4. Probe 4: handler Proc を `Ractor.make_shareable(proc, copy: true)` で shareable 化 → 別 Ractor 内 `body.call(args)` 動作
5. Probe 5: `informers` の ONNX 推論を別 Ractor 内で実行 (gem の Ractor 適合確認)

判定:
- 1〜4 全 pass → spec 通り B 採用、実装続行
- 4 だけ fail (closure 制限が現実的でない) → handler は Main Ractor で同期実行、State Ractor (shareable_ref) のみ Ractor 化、UX の「並行 readline」は諦め
- 1〜3 のいずれか fail → curses or Reline が Ractor で動かない、Plan 全面再考 (戦略 A への切替を協議)

# Out of scope (v2 以降)

- 段階移行 / backward compat shim
- intent grid + actual grid の divergence detection
- triple-lane 動画 (intent/actual/diff)
- 注釈付き動画 (frame metadata overlay)
- 純 Ruby PNG renderer (現 v1 は agg + ffmpeg 外部依存)
- web viewer / replay subcommand
- 多 session 集約 query (per-session DB merge スクリプトは v2)
- 複数 example shell の並列 debug 集約
- handler の cancel / retry プリミティブ
- mouse interaction (curses 標準 `mousemask` で v2 実装可能)

# Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Reline が Main Ractor で動かない | Probe Task 0 で先行検証、fail なら戦略再考 |
| curses gem (libncurses) が Ractor 跨ぎで bug | curses は Main Ractor 専有、cross-Ractor 呼出ゼロ |
| handler 内 closure 捕捉が `make_shareable` で破綻 | `shareable_ref` パターン提示 + drop-in 移行ガイド |
| informers (ONNX) が Ractor 内で SEGV | embedder Ractor 単独 process / fallback で thread (限定的) |
| chiebukuro-mcp 登録が壊れる | `_sqlite_mcp_meta` 互換性を test で fixture 検証 |
| 既存 examples 移行コスト | echo_shell は Time のみ捕捉なので無傷、irb_shell は shareable_ref 化に集中 |
| WAL contention (recorder + viewer 並行 read) | SQLite WAL mode で並行 OK、viewer は readonly |
