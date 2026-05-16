# frozen_string_literal: true

require "reline"
require "timeout"
require_relative "display"
require_relative "context"
require_relative "main_ctx"
require_relative "title_bar"

module Baslash
  # Reline dialog procs + Main-thread mailbox drain. Drives TitleBar (OSC 0)
  # for status display. Provides the slash menu / ghost text dialog procs
  # and apply_command dispatcher; per-tick repaint (`run_tick`) writes the
  # terminal title.
  module RelineDialogs
    SLASH_NAME_PAD = 16

    # Reline's default keyseq_timeout (500ms) doubles as the periodic_tick
    # cadence — dialog procs only re-fire after a keystroke OR a timeout.
    # Keep it short so periodic_tick fires several times per second when
    # the user is idle (TitleBar spinner cadence). Keep >= 100ms so that
    # genuine escape-sequence input (arrow keys etc.) still arrives as a
    # single keyseq.
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

    class << self
      attr_accessor :stub_apply_command_for_test

      def install(builder)
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

      def periodic_tick_proc(builder)
        main_ctx = Baslash::MainCtx.new(builder.state_refs)
        proc do
          # If Reline is in completion-journey mode (Tab pressed and a
          # journey is active), it owns the terminal — skip the tick so
          # we do not stomp on its in-progress paint.
          jd = (completion_journey_data rescue nil)
          next nil if jd

          Baslash::RelineDialogs.run_tick(builder, main_ctx)
          nil
        end
      end

      # Per-tick repaint. Drains the Main-thread mailbox (apply_command),
      # then writes the terminal title via OSC 0 (TitleBar.tick) reflecting
      # current phase + composed info_bar/status_rows text.
      def run_tick(builder, main_ctx)
        drain_main_mailbox
        phase = (Baslash::Context.state[:phase] rescue nil) || :ready
        ctx_text = compose_ctx_text(builder, main_ctx)
        Baslash::TitleBar.tick(phase: phase, ctx_text: ctx_text)
      rescue StandardError => e
        Baslash::Context.logger.error("tick failed: #{e.class}: #{e.message}") rescue nil
        nil
      end

      # Joins all non-empty info_bar texts + status_row segment texts with
      # " · ". Returns "" when nothing is registered. The result is the
      # ctx_text passed to TitleBar.tick.
      def compose_ctx_text(builder, main_ctx)
        parts = []
        builder.evaluate_info_bar(main_ctx).each do |item|
          t = (item[:text] || item["text"]).to_s
          parts << t unless t.empty?
        end
        builder.evaluate_status_rows(main_ctx).each do |row|
          segs = row[:segments] || row["segments"] || []
          text = segs.map { |s| (s[:text] || s["text"]).to_s }.reject(&:empty?).join(" ")
          parts << text unless text.empty?
        end
        parts.join(" · ")
      end

      # Current line under the cursor in Reline's editor. Reline >= 0.6
      # dropped the @line ivar in favor of @buffer_of_lines (Array<String>)
      # + @line_index (Integer); reading @line directly silently returned
      # nil and made the slash-menu dialog never fire. Returns "" instead
      # of nil so callers can do `.start_with?` without an extra nil check.
      def current_buffer_line(line_editor)
        return "" unless line_editor
        bol = line_editor.instance_variable_get(:@buffer_of_lines)
        idx = line_editor.instance_variable_get(:@line_index) || 0
        return "" unless bol.is_a?(Array)
        bol[idx].to_s
      end

      def slash_menu_dialog_proc(registry)
        proc {
          line = Baslash::RelineDialogs.current_buffer_line(@line_editor)
          cx   = (cursor_pos.x rescue 0)
          next nil unless line.is_a?(String) && line.start_with?("/")
          typed = line[0, cx].to_s
          m = typed.match(/\A\/(\S*)/)
          next nil unless m
          prefix = m[1]
          items =
            begin
              registry.slash_menu_items_starting_with(prefix)
            rescue StandardError => err
              Baslash::Context.logger.error("slash_menu lookup failed: #{err.class}: #{err.message}") rescue nil
              []
            end
          next nil if items.empty?
          contents = Baslash::RelineDialogs.format_slash_lines(items)
          x = [cx - typed.bytesize, 0].max
          height = [contents.size, 12].min
          Reline::DialogRenderInfo.new(
            pos:      Reline::CursorPos.new(x, 0),
            contents: contents,
            height:   height,
            width:    Baslash::RelineDialogs.dialog_width(contents),
            face:     :default
          )
        }
      end

      def ghost_text_dialog_proc(registry, ctx)
        proc {
          next nil if completion_journey_data
          line = Baslash::RelineDialogs.current_buffer_line(@line_editor)
          next nil unless line.empty?
          hint = begin
            registry.current_prompt_suggestion(ctx)
          rescue StandardError
            nil
          end
          formatted = Baslash::RelineDialogs.format_ghost_hint(hint)
          next nil unless formatted
          Reline::DialogRenderInfo.new(
            pos:      Reline::CursorPos.new(0, 0),
            contents: [formatted],
            height:   1,
            width:    Baslash::RelineDialogs.visible_width(formatted),
            face:     :default
          )
        }
      end

      def format_slash_line(item)
        name = item[:name].to_s
        desc = item[:description].to_s
        return name if desc.empty?
        pad = [SLASH_NAME_PAD - name.bytesize, 1].max
        "#{name}#{' ' * pad}\e[2;90m#{desc}\e[0m"
      end

      def format_slash_lines(items)
        items.map { |item| format_slash_line(item) }
      end

      def visible_width(line)
        line.gsub(/\e\[[0-9;]*m/, "").bytesize
      end

      def dialog_width(lines)
        return 0 if lines.empty?
        lines.map { |l| visible_width(l) }.max
      end

      def format_ghost_hint(text)
        return nil if text.nil? || text.to_s.empty?
        "\e[2;90m#{text}\e[0m"
      end

      def drain_main_mailbox
        handler = stub_apply_command_for_test || method(:apply_command)
        100.times do
          msg = peek_mailbox
          break unless msg
          handler.call(msg)
        end
      end

      def peek_mailbox
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

      def apply_command(msg)
        case msg
        in [:append, text, opts]
          Baslash::Display.append(text, **opts)
        in [:open_live_request, reply_to, opts]
          sid = Baslash::Display.open_live(**opts)
          reply_to.send([:open_live_reply, sid])
        in [:live_update, sid, text]
          Baslash::Display.live_update(sid, text)
        in [:live_commit, sid, final]
          Baslash::Display.live_commit(sid, final)
        in [:live_discard, sid]
          Baslash::Display.live_discard(sid)
        in [:dialog, content, opts]
          Baslash::Display.dialog(content, **opts)
        in [:emit, bytes]
          $stdout.write(bytes)
          $stdout.flush
        in [:state_set, key, value]
          Baslash::Context.state_set(key, value)
        in [:state_get_request, reply_to, key]
          reply_to.send([:state_get_reply, Baslash::Context.state[key]])
        in [:debug_snapshot_request, reply_to]
          snapshot = {
            context_state:   Baslash::Context.state.inspect,
            title_bar_phase: Baslash::TitleBar.last_phase.inspect
          }.freeze
          reply_to.send([:debug_snapshot_reply, snapshot])
        in [:debug_tick_count_request, reply_to]
          reply_to.send([:debug_tick_count_reply, Baslash::TitleBar.tick_count])
        in [:debug_curses_caps_request, reply_to]
          reply_to.send([:debug_curses_caps_reply, { term: ENV["TERM"].to_s.freeze }])
        in [:logger, level, text]
          Baslash::Context.logger.send(level, text) rescue nil
        in [:quit]
          Baslash::Context.quit
        else
          # Unknown message — ignore
        end
      end
    end
  end
end
