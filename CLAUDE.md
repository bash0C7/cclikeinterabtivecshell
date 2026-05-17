# CLAUDE.md — baslash project instructions

このファイルは baslash リポジトリで作業する LLM / 開発者向けのプロジェクト固有ガイド。
README はユーザ向け、こちらは開発者・AI 向け。

## Project overview

**baslash** は macOS 向けの slash 駆動 Ruby シェルフレームワーク。Reline ベースの REPL に
slash コマンド (`/foo`) DSL・OSC 0 タイトルバー・同期ハンドラ dispatch を載せたもの。
本体 `baslash` gem 単独で完結する。PTY 録画や session 分析は外部ツール
[ptyblues](https://github.com/bash0C7/ptyblues) で行う（runtime/gemspec 依存なし）。

## Directory layout

| Path                       | 役割                                                            |
| -------------------------- | --------------------------------------------------------------- |
| `lib/baslash.rb`           | エントリポイント。全モジュールを require                          |
| `lib/baslash/`             | フレームワーク本体（builder / runner / sync_ctx / display 等）   |
| `examples/echo_shell.rb`   | 最小サンプル（DSL の典型）                                       |
| `examples/zsh_shell/`      | 最も網羅的なサンプル。新しい DSL 利用例を見るならここ            |
| `examples/irb_shell/`      | irb 風サンプル（Ractor 経由の評価器）                            |
| `test/`                    | 本体テストスイート（test-unit）                                  |
| `examples/ptyblues_recording/` | 外部ツール ptyblues を使った録画 + 分析 + E2E サンプル群        |
| `docs/superpowers/`        | **gitignored** な設計ドキュメント（specs / plans / handoff）      |
| `Rakefile`                 | `rake test` だけ                                                  |

`docs/superpowers/` は `.gitignore` に入っているので、コミットしたければ `git add -f` 必須。

## Build / test commands

```bash
bundle install

# 本体テスト
bundle exec rake test
```

`test/test_thread_zero.rb` が `lib/` と `examples/` の `Thread.new` / `Thread.fork` /
`Thread.start` を機械的に禁止する。並行性が要るなら **Ractor を使う**。

### Test execution delegation

大きなスイートは subagent (`general-purpose` か `commit-commands` skill) に委譲して
pass/fail と件数だけ返してもらうのが好ましい（make ログ / dot 進行で main context を
汚さない）。単発デバッグ（`-n test_x`）は Bash 直叩き可。

## Architecture invariants（自明でない部分）

- **同期 dispatch がデフォルト**。slash / on_submit ハンドラは main thread で走る。
  HandlerRactor は将来の "explicit background" モード用にディスクには残っているが、
  `lib/baslash.rb` から require されていない。
- **`SyncCtx` が per-invocation の ctx**（`lib/baslash/sync_ctx.rb`）。
  Display / Context / state_refs に直接話す。CtxProxy は CtxProxy で、
  ハンドラ側からは見えない。
- **curses も alt-screen も使わない**。本文は `puts` で stdout に直書き → 端末のネイティブ
  scrollback がそのまま使える。ステータスは OSC 0 でタイトルバーに出す。
- **slash body は素の Proc**。closure capture が普通に効く。`SlashRegistry.register`
  （`lib/baslash/slash_registry.rb`）は `Ractor.shareable_proc` を呼ばない。
- **タイトルバーは OSC 0 経由**。`Baslash::TitleBar.tick(phase:, ctx_text:)` で更新。
  同期ハンドラ実行中は `Baslash::WorkingIndicator`（Ractor）が ~120ms 間隔で
  スピナーフレームを流し続ける。

## Coding conventions

### Silent rescue 禁止（プロジェクト共通）

- `rescue nil` / 空 `rescue` / `rescue ... => _` パターン禁止
- production コード: `re-raise` / 構造化ログ / Result 返却 のいずれか
- テスト: `omit "reason: #{e.message}"` でスキップ理由を可視化
- cclikesh から ported された既存パターンは黙認するが、**新規追加は不可**

### File pragma

- `lib/` 配下の全ファイル: `# frozen_string_literal: true` 必須
- テストファイル: 任意（強制はしない）

### Style module (`lib/baslash/style.rb`)

`Style.apply(:name, text)` の順序:

1. semantic style (`:ok` `:ng` `:error` `:warn` `:thinking` `:meta`)
2. named style (`:bold` `:dim` `:italic` `:underline` `:reverse`)
3. named color (`:red` `:green` `:cyan` ...)
4. その他 / `nil` → そのまま返す

`:result` は **意図的に未定義**。impl の stdout は端末デフォルト色に保つため
`Style.apply(:result, ...)` は素通しになる。

semantic 一覧:

| Symbol     | SGR     | 用途                  |
| ---------- | ------- | --------------------- |
| `:ok`      | green   | success status        |
| `:ng`      | red     | failure status        |
| `:error`   | red     | error messages        |
| `:warn`    | yellow  | warnings              |
| `:thinking`| dim cyan| in-progress live slot |
| `:meta`    | dim cyan| framework metadata    |

## Git workflow

- **`git commit --amend` 禁止**。常に新規 commit
- conventional commits（`feat:` / `fix:` / `chore:` / `docs:` / `test:`）
- commit message は **English only**
- 明示的に承認されるまで `git push` しない
- `git status` / `diff` / `commit` 等は subagent
  （`commit-commands` skill or `general-purpose`）に委譲して main context を汚さない

## Testing pattern

- TDD: failing test → impl → red→green 確認
- 巨大スイートは subagent 委譲（pass/fail + count のみ取得）
- single test debug は Bash 直叩き OK

## ptyblues integration (external tool)

baslash は外部ツール [ptyblues](https://github.com/bash0C7/ptyblues) に
**runtime / gemspec 依存しない**。連携は外部プロセス関係のみ
(`bundle exec ttyblues ...`)。手順とサンプルは:

- 動くサンプル: `examples/ptyblues_recording/`（録画 / 分析 / 自動 E2E 3 種）
- README Appendix: `README.md` の末尾「Appendix: Recording & Analysis with ptyblues」

開発便利性のため root `Gemfile` の `group :development, :test` に
ptyblues monorepo の sub-gem 連鎖を sibling path (`../ptyblues`,
`../ptyblues/record`, `../ptyblues/viewer`, `../ptyblues/inspect`,
`../ptyblues/client-druby`, `../ptyblues/client-cli`) で resolve してある。
`bundle install` 後すぐ `bundle exec ttyblues …` が叩ける。

ptyblues 側の変更・撤去・非インストールは baslash の `rake test` に
**何の影響も与えない**（依存ゼロのため）。

## Common pitfalls

- **closure capture が slash body で効かない場合**: `block.call` が nil を呼んでたら、
  誰かが `SlashRegistry.register` に `Ractor.shareable_proc` を再追加した可能性。戻すこと。
- **`prompt_prefix` の block**: `MainCtx`（SyncCtx ではない）が渡る。
  ハンドラ呼び出しの合間に評価される。
- **HandlerRactor 関連テスト**: "deferred until explicit-background mode" として omit 済み。
  failing test として直そうとしないこと。
- **`examples/irb_shell`**: 既存の `Ractor.new: allocator undefined for Binding` バグあり。
  smoke test は omit 済み。

## Adding a new slash command

1. Builder block 内で:
   ```ruby
   shell.slash(:name, description: "...") do |args, ctx|
     ctx.display.append("hi", style: :result)
   end
   ```
2. 出力は `ctx.display.append(text, style: :result)`（impl 内容、端末デフォルト色）
3. エラーは `ctx.display.append(text, style: :error)`（赤）
4. 長い処理は同期で書いて OK。Ctrl-C で abort できる
5. 呼び出し間で mutable state を持ちたければ:
   ```ruby
   shell.shareable_ref(:holder) { Holder.new }
   # 後で
   ctx.shareable(:holder).call(:method, arg)
   ```

## Adding a new app on top of baslash

1. `require "baslash"`
2. `Baslash.run do |shell| ... end` で Builder DSL を使う
3. テンプレートは `examples/echo_shell.rb` がシンプル、`examples/zsh_shell/zsh_shell.rb` が網羅的
4. パイプ入力で smoke test:
   ```bash
   printf '/test\n/exit\n' | bundle exec ruby my_shell.rb
   ```
5. 対話機能（slash menu / Tab cycle / multi-line / Ctrl-C abort）は Terminal.app で
   実 TTY 検証必須

## When in doubt

- `examples/zsh_shell/zsh_shell.rb` — 最も網羅的な使用例
- `lib/baslash/builder.rb` — DSL の正式シグネチャ
- `lib/baslash/sync_ctx.rb` — ハンドラに渡る ctx の表面
- `docs/superpowers/handoff/2026-05-16-baslash-v1-shipped.md` — v1 出荷時サマリ
