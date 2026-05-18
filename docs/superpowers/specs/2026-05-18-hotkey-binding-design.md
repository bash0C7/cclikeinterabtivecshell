# Hotkey binding for slash commands — design

Date: 2026-05-18
Status: design approved, awaiting plan

## Goal

Let baslash app authors (and the framework itself) bind a keyboard
**hotkey** to a slash command so that pressing the key from an empty
prompt dispatches the command without typing `/<name><Enter>`. The
feature is fully opt-in: by default every command has **no hotkey**.

## Vocabulary

The user's term for this feature is **hotkey**, not "shortcut". Use
`hotkey:` in the DSL and `Hotkey*` in module names. The existing
`shortcuts_hint` DSL (startup one-line hint string) is a separate
concept and is not touched by this design.

## DSL surface

Single entry point, the same `shell.slash` that already registers
commands. New keyword argument `hotkey:` (default `nil`).

```ruby
shell.slash(:reset, description: "reset state", hotkey: "C-g") do |args, ctx|
  ctx.state[:cwd].reset
end
```

Calling `shell.slash(name, hotkey: ...)` **without a block** updates
only the metadata (description / hotkey) of an already-registered
entry. This is the supported way to attach a hotkey to a framework
built-in such as `/exit` or `/help` without redefining its body:

```ruby
shell.slash(:exit, hotkey: "C-d")   # binds C-d to the built-in /exit
```

If the named entry does not exist, the block-less form raises
`Baslash::HotkeyError` (or a sibling `Baslash::SlashRegistryError`).
Re-registering with a block replaces body, description, and hotkey as
a whole (existing behaviour for body, new for hotkey).

## Key-spec grammar (v1)

Strings only — emacs / Reline tradition.

| Form          | Example      | Byte sequence       |
| ------------- | ------------ | ------------------- |
| `C-<letter>`  | `"C-g"`      | `[7]`               |
| `M-<letter>`  | `"M-d"`      | `[27, 100]`         |
| `M-<digit>`   | `"M-1"`      | `[27, 49]`          |
| chord         | `"C-x C-r"`  | `[24, 18]`          |

Case-insensitive. Whitespace between chord tokens is one or more spaces.
Anything else — function keys, arrow keys, raw byte arrays, multi-char
chords beyond Ctrl+letter / Meta+letter / Meta+digit — is **out of
scope for v1** and raises `Baslash::HotkeyError`.

Reserved (binding raises):

| Key      | Reason                                          |
| -------- | ----------------------------------------------- |
| `C-c`    | SIGINT — must keep interrupting handlers        |
| `C-m`    | Enter (CR) — submits the line                   |
| `C-j`    | LF — submits the line                           |
| `C-i`    | Tab — slash menu / completion                   |
| `C-h`    | Backspace                                       |

## Runtime behaviour

When the bound key is pressed:

1. **Buffer-empty gate.** If `@buffer_of_lines.size != 1` or
   `current_line` (the row under the cursor) is non-empty, the
   hotkey is a no-op. The user is in the middle of typing or in a
   multi-line edit and we must not stomp on the buffer.
2. **Dispatch path unification.** When the gate passes, the handler
   calls `set_current_line("/#{name}", bytesize)` and then `finish`,
   which makes Reline's `readmultiline` return `"/<name>"` on the
   normal submit path. The runner then hands it to
   `SlashDispatcher.handle` exactly as if the user had typed it. There
   is **one** dispatch path; the hotkey is just an alternate way to
   produce the line.
3. Arguments are always empty (`args == []`). Hotkeys do not carry
   arguments in v1.

## Reline integration (Approach A)

Reline 0.6.3 dispatches a key sequence to a method name via
`Reline::LineEditor#__send__(method_symbol)` after
`respond_to?(method_symbol, true)`. Proc/lambda targets are **not**
supported, so the implementation must register a real instance method
on `Reline::LineEditor`.

`Baslash::HotkeyInstaller.install(builder)`:

```ruby
builder.slash_registry.each do |name, entry|
  spec = entry[:hotkey]
  next unless spec
  bytes       = Baslash::HotkeySpec.parse(spec)
  method_name = :"__baslash_hotkey_#{name}"

  unless Reline::LineEditor.private_method_defined?(method_name) ||
         Reline::LineEditor.method_defined?(method_name)
    Reline::LineEditor.define_method(method_name) do |key|
      next unless @buffer_of_lines.size == 1 && current_line.empty?
      line = "/#{name}"
      set_current_line(line, line.bytesize)
      finish
    end
  end

  Reline.core.config.add_default_key_binding(bytes, method_name)
end
```

Method names are namespaced with `__baslash_hotkey_` so they do not
collide with Reline built-ins. Installation runs **after**
`DefaultCommands.register` / `register_help`, ensuring built-in
commands (`/exit /q /help`) can also pick up hotkeys assigned in the
user's builder via the no-block form.

Conflict on the same byte sequence: Reline's `KeyActor::Base#add`
overwrites silently. We log a warning at install time
(`logger.warn("hotkey conflict: ... -> last wins")`) when we detect
the same bytes registered twice in the same install pass.

## Discoverability

### `/help`

`DefaultCommands.register_help` snapshots the registry at registration
time. Extend the snapshot tuple to include the hotkey string:

```ruby
existing << [name.to_s, entry[:description].to_s, entry[:hotkey].to_s].freeze
```

Rendering:

```
/reset  - reset state            (C-g)
/exit   - exit                   (C-d)
/help   - list slash commands
```

Hotkey suffix is rendered with the existing dim style. Padding to a
fixed column keeps it visually grouped. Commands without a hotkey omit
the suffix entirely (no `()` placeholder).

### Slash menu dialog

`SlashRegistry#slash_menu_items_starting_with` returns
`{ name:, description:, hotkey: }`. `RelineDialogs.format_slash_line`
appends ` (C-g)` (dim) to the existing description column when
`hotkey` is non-empty.

### Not changed

- `shortcuts_hint` text remains user-controlled. No automatic injection.
- No dedicated `/keys` command in v1.

## Files

New:

| Path                                | Role                                                                    |
| ----------------------------------- | ----------------------------------------------------------------------- |
| `lib/baslash/hotkey_spec.rb`        | `parse(str) -> [Integer]`, `format(bytes) -> String`, reserved check    |
| `lib/baslash/hotkey_installer.rb`   | iterate registry, install method + binding into Reline::LineEditor      |
| `test/test_hotkey_spec_baslash.rb`      | unit tests for parse / format / reserved / invalid                      |
| `test/test_hotkey_installer_baslash.rb` | unit tests covering buffer-empty gate, conflict warning, no-hotkey skip |

Changed:

| Path                                | Change                                                                       |
| ----------------------------------- | ---------------------------------------------------------------------------- |
| `lib/baslash/slash_registry.rb`     | `register` accepts `hotkey:`; entry stores it; menu items include `:hotkey`  |
| `lib/baslash/builder.rb`            | `slash` accepts `hotkey:`; no-block form updates existing entry              |
| `lib/baslash/runner.rb`             | call `HotkeyInstaller.install(builder)` after `DefaultCommands.register_help`|
| `lib/baslash/reline_dialogs.rb`     | `format_slash_line` appends ` (hotkey)` in dim                               |
| `lib/baslash/default_commands.rb`   | `register_help` snapshot includes hotkey; renders suffix                     |
| `lib/baslash.rb`                    | require the two new files                                                    |
| `README.md`                         | document `hotkey:` kwarg under the DSL table; note default-off and reserved keys |
| `examples/zsh_shell/zsh_shell.rb`   | one demonstrative `hotkey: "C-g"` on `/reset` so the feature is exercised live |
| `test/test_slash_registry_baslash.rb` | extend coverage for `hotkey` field (existing file)                         |
| `test/test_builder_baslash.rb`      | extend coverage: `slash` accepts `hotkey:`, no-block update form, errors     |
| `test/test_default_commands_baslash.rb` | extend coverage: `/help` snapshot includes hotkey suffix                  |
| `test/test_reline_dialogs_baslash.rb` | extend coverage: `format_slash_line` renders hotkey suffix                 |

## Errors and logging

- Invalid spec (`"foo"`, `"C-"`, empty) → `Baslash::HotkeyError` at
  `Builder#slash` call time. No silent rescue.
- Reserved key (`"C-c"` etc.) → `Baslash::HotkeyError`.
- No-block update against unknown name → `Baslash::HotkeyError`.
- Duplicate byte sequence across two commands → `logger.warn(...)`,
  last write wins.
- All errors and warnings go through `builder.logger` (already wired).

## Testing

Unit (test-unit, `rake test`):

- `HotkeySpec.parse` happy path: `"C-g"`, `"M-d"`, `"M-1"`, `"C-x C-r"`,
  case-insensitive variants.
- `HotkeySpec.parse` errors: empty string, `"foo"`, `"C-"`, `"X-y"`,
  multi-char meta like `"M-foo"`.
- `HotkeySpec.parse` reserved: `"C-c"`, `"C-m"`, `"C-j"`, `"C-i"`,
  `"C-h"` raise.
- `HotkeySpec.format` round-trip.
- `SlashRegistry#register` stores `hotkey:` and exposes it via
  `slash_menu_items_starting_with`.
- `Builder#slash` no-block form: updates an existing entry's hotkey,
  raises on unknown name.
- `RelineDialogs.format_slash_line` produces the expected line with
  and without hotkey.
- `DefaultCommands.register_help` produces help output containing the
  hotkey suffix when one is registered.
- `HotkeyInstaller`: when registry has two commands sharing the same
  parsed byte sequence, the second registration emits a warn.

E2E (TTY-only, `examples/ptyblues_recording/`):

- Add a small recording-based test: bind `C-g` to a `/marker` command
  that prints a sentinel string. Send `C-g` (raw byte `\a` / `\x07`)
  to the pty and assert the sentinel appears in transcript.
- Send `abc` then `C-g` and assert the sentinel does **not** appear
  (buffer-empty gate).

Out of scope for v1:

- Function keys, arrow keys, raw byte arrays.
- Hotkey with arguments (`hotkey: "C-g", default_args: ["foo"]`).
- Per-mode bindings (Reline `editing_mode`).
- Run-time rebind via slash command (`/bind C-g /reset`).

## Open considerations / rejected alternatives

- **Approach C (lambda binding to `key_bindings.add`)** was investigated
  and rejected: Reline 0.6.3 dispatches via `__send__(symbol)` and the
  `respond_to?(symbol, true)` guard rules out Proc targets. Confirmed
  in `lib/reline/line_editor.rb` `wrap_method_call` (line 949).
- **Approach B (`periodic_tick` polling a flag)** introduces up to
  120 ms latency between keypress and dispatch, and grows the
  responsibility of the tick proc which already handles OSC 0 paint.
  Rejected.
- **Buffer-non-empty mode** ("press C-g any time → discard buffer and
  run") was explicitly rejected by the user — only the buffer-empty
  gate is desired.
- **Insert-mode hotkey** ("press C-g → put `/reset ` in buffer, do not
  submit") was rejected. Only run-on-press is supported.
- **Dedicated `/keys` command** was not requested. Help row + dialog
  suffix is enough for v1.

## Backwards compatibility

- `SlashRegistry#register` gains a new `hotkey:` kwarg with `nil`
  default. Existing callers continue to work without changes.
- `slash_menu_items_starting_with` returns items with an extra
  `:hotkey` key; callers that rely on hash shape (only
  `RelineDialogs.format_slash_line` and tests) are updated.
- `Builder#slash` block-less form is new behaviour; previous calls
  always passed a block.
