# frozen_string_literal: true

require "reline"
require "timeout"
require_relative "chrome"
require_relative "display"
require_relative "context"
require_relative "reline_idle_patch"

module Cclikesh
  module RelineDialogs
    SLASH_NAME_PAD = 16

    class << self
      attr_accessor :stub_apply_command_for_test
    end

    def self.format_slash_line(item)
      name = item[:name].to_s
      desc = item[:description].to_s
      return name if desc.empty?
      pad = [SLASH_NAME_PAD - name.bytesize, 1].max
      "#{name}#{' ' * pad}\e[2;90m#{desc}\e[0m"
    end

    def self.format_slash_lines(items)
      items.map { |item| format_slash_line(item) }
    end

    def self.visible_width(line)
      line.gsub(/\e\[[0-9;]*m/, "").bytesize
    end

    def self.dialog_width(lines)
      return 0 if lines.empty?
      lines.map { |l| visible_width(l) }.max
    end

    def self.format_ghost_hint(text)
      return nil if text.nil? || text.to_s.empty?
      "\e[2;90m#{text}\e[0m"
    end

    def self.slash_menu_dialog_proc(registry)
      base = Reline::DEFAULT_DIALOG_PROC_AUTOCOMPLETE
      proc {
        jd = completion_journey_data
        target = jd && jd.list && jd.list.first
        if target.is_a?(String) && target.start_with?("/")
          prefix = target[1..]
          items = begin
            registry.slash_menu_items_starting_with(prefix)
          rescue StandardError
            []
          end
          if items.empty?
            instance_exec(&base)
          else
            contents = Cclikesh::RelineDialogs.format_slash_lines(items)
            x = [cursor_pos.x - target.bytesize, 0].max
            Reline::DialogRenderInfo.new(
              pos:      Reline::CursorPos.new(x, 0),
              contents: contents,
              height:   contents.size,
              width:    Cclikesh::RelineDialogs.dialog_width(contents),
              face:     :default
            )
          end
        else
          instance_exec(&base)
        end
      }
    end

    def self.ghost_text_dialog_proc(registry, ctx)
      proc {
        next nil if completion_journey_data
        line = @line_editor.instance_variable_get(:@line) rescue nil
        next nil unless line.nil? || line.empty?
        hint = begin
          registry.current_prompt_suggestion(ctx)
        rescue StandardError
          nil
        end
        formatted = Cclikesh::RelineDialogs.format_ghost_hint(hint)
        next nil unless formatted
        Reline::DialogRenderInfo.new(
          pos:      Reline::CursorPos.new(0, 0),
          contents: [formatted],
          height:   1,
          width:    Cclikesh::RelineDialogs.visible_width(formatted),
          face:     :default
        )
      }
    end

    # Reline's default keyseq_timeout (500ms) doubles as the periodic_tick
    # cadence — dialog procs only re-fire after a keystroke OR a timeout.
    # We want the footer spinner to animate at roughly Claude Code's speed
    # (~105ms/frame), so shorten the timeout enough that periodic_tick
    # fires several times per second when the user is idle. We keep it at
    # >= 100ms so that genuine escape-sequence input (arrow keys etc.)
    # still gets time to arrive as a single keyseq.
    PERIODIC_TICK_TIMEOUT_MS = 120

    # Byte sequences emitted by terminals for Shift+Enter when
    # modifyOtherKeys mode 2 is enabled (xterm/iTerm2/ghostty/wezterm) or
    # the kitty keyboard protocol is in use. Both decode to "Enter with
    # the Shift modifier" — we bind them to key_newline so they insert a
    # literal newline instead of submitting the line.
    SHIFT_ENTER_KEYSTROKES = [
      "\e[27;2;13~".bytes,  # modifyOtherKeys mode 2 (xterm/iTerm2)
      "\e[13;2u".bytes      # CSI u / kitty kbd protocol
    ].freeze

    def self.install(builder)
      registry = builder.slash_registry
      if Reline.core.config.keyseq_timeout > PERIODIC_TICK_TIMEOUT_MS
        Reline.core.config.keyseq_timeout = PERIODIC_TICK_TIMEOUT_MS
      end
      SHIFT_ENTER_KEYSTROKES.each do |keys|
        Reline.core.config.add_default_key_binding(keys, :key_newline)
      end
      Reline.add_dialog_proc(:periodic_tick, periodic_tick_proc(builder), Reline::DEFAULT_DIALOG_CONTEXT)
      Reline.add_dialog_proc(:autocomplete, slash_menu_dialog_proc(registry), Reline::DEFAULT_DIALOG_CONTEXT)
      Reline.add_dialog_proc(:ghost_text, ghost_text_dialog_proc(registry, nil), Reline::DEFAULT_DIALOG_CONTEXT)
    end

    def self.periodic_tick_proc(builder)
      main_ctx = Cclikesh::MainCtx.new(builder.state_refs)
      proc do
        # If Reline is in completion-journey mode (Tab pressed and a journey
        # is active), it owns the terminal — don't paint, otherwise our
        # curses repaint resets cursor mid-render and the input line
        # disappears until the user types another character.
        jd = (completion_journey_data rescue nil)
        next nil if jd

        Cclikesh::RelineDialogs.run_chrome_tick(builder, main_ctx)
        nil
      end
    end

    # Shared body of the chrome repaint. Called from periodic_tick_proc
    # (on key input) and from the background tick thread started by
    # Runner.run (on a 100ms timer while idle). The caller is responsible
    # for holding the curses mutex.
    def self.run_chrome_tick(builder, main_ctx)
      # Wrap the curses repaint in DECSC / DECRC (\e7 / \e8) so the
      # physical cursor returns to whatever column Reline last placed it
      # at. Using \e[N;1H (CUP, absolute) here desynced Reline's relative
      # cursor tracking and caused it to erase the prompt prefix `>` on
      # the next keystroke.
      phase = Cclikesh::Context.state[:phase]
      Cclikesh::Chrome.tick_spinner(phase)
      $stdout.print("\e7")
      $stdout.flush
      drain_main_mailbox
      Cclikesh::Chrome.update_footer(
        info_bar:       builder.evaluate_info_bar(main_ctx),
        status_rows:    builder.evaluate_status_rows(main_ctx),
        shortcuts_hint: builder.shortcuts_hint_text,
        phase:          phase
      )
      Curses.doupdate rescue nil
      $stdout.print("\e8")
      $stdout.flush
    end

    def self.drain_main_mailbox
      handler = stub_apply_command_for_test || method(:apply_command)
      100.times do
        msg = peek_mailbox
        break unless msg
        handler.call(msg)
      end
    end

    def self.peek_mailbox
      # Try non-blocking Ractor.receive_if with timeout: 0
      # (Ruby 4.0 does not have receive_if, so rescue NoMethodError/ArgumentError)
      Ractor.receive_if(timeout: 0) { true }
    rescue NoMethodError, ArgumentError
      # Fallback: Timeout-based non-blocking receive
      begin
        Timeout.timeout(0.001) { Ractor.receive }
      rescue Timeout::Error
        nil
      end
    end

    def self.apply_command(msg)
      case msg
      in [:append, text, opts]
        Cclikesh::Display.append(text, **opts)
      in [:open_live_request, reply_to, opts]
        sid = Cclikesh::Display.open_live(**opts)
        reply_to.send([:open_live_reply, sid])
      in [:live_update, sid, text]
        Cclikesh::Display.live_update(sid, text)
      in [:live_commit, sid, final]
        Cclikesh::Display.live_commit(sid, final)
      in [:live_discard, sid]
        Cclikesh::Display.live_discard(sid)
      in [:dialog, content, opts]
        Cclikesh::Display.dialog(content, **opts)
      in [:emit, bytes]
        $stdout.write(bytes)
        $stdout.flush
        Curses.stdscr.touch
        Curses.doupdate rescue nil
      in [:state_set, key, value]
        Cclikesh::Context.state_set(key, value)
      in [:state_get_request, reply_to, key]
        reply_to.send([:state_get_reply, Cclikesh::Context.state[key]])
      in [:debug_snapshot_request, reply_to]
        snapshot = {
          context_state:      Cclikesh::Context.state.inspect,
          spinner_started_at: Cclikesh::Chrome.spinner_started_at.inspect,
          breath_supported:   Cclikesh::Chrome.breath_supported.inspect
        }.freeze
        reply_to.send([:debug_snapshot_reply, snapshot])
      in [:debug_tick_count_request, reply_to]
        reply_to.send([:debug_tick_count_reply, Cclikesh::RelineIdlePatch.tick_history.size])
      in [:debug_curses_caps_request, reply_to]
        require "curses"
        attrs = %w[A_NORMAL A_BOLD A_DIM A_UNDERLINE A_REVERSE A_STANDOUT A_BLINK A_INVIS A_PROTECT A_ALTCHARSET A_ITALIC]
        caps = {
          term:              ENV["TERM"].to_s.freeze,
          colors:            (Curses::COLORS rescue "n/a"),
          color_pairs:       (Curses::COLOR_PAIRS rescue "n/a"),
          can_change_color:  (Curses.can_change_color? rescue "n/a"),
          defined_attrs:     attrs.select { |a| Curses.const_defined?(a) }.freeze
        }.freeze
        reply_to.send([:debug_curses_caps_reply, caps])
      in [:logger, level, text]
        Cclikesh::Context.logger.send(level, text) rescue nil
      in [:quit]
        Cclikesh::Context.quit
      else
        # Unknown message — ignore
      end
    end
  end
end
