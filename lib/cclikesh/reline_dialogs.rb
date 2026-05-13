# frozen_string_literal: true

require "reline"
require "timeout"
require_relative "chrome"
require_relative "display"
require_relative "context"

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

    def self.install(builder)
      registry = builder.slash_registry
      Reline.add_dialog_proc(:periodic_tick, periodic_tick_proc(builder), Reline::DEFAULT_DIALOG_CONTEXT)
      Reline.add_dialog_proc(:autocomplete, slash_menu_dialog_proc(registry), Reline::DEFAULT_DIALOG_CONTEXT)
      Reline.add_dialog_proc(:ghost_text, ghost_text_dialog_proc(registry, nil), Reline::DEFAULT_DIALOG_CONTEXT)
    end

    def self.periodic_tick_proc(builder)
      main_ctx = Cclikesh::MainCtx.new(builder.state_refs)
      proc do
        Cclikesh::RelineDialogs.drain_main_mailbox
        Cclikesh::Chrome.update_footer(
          info_bar:       builder.evaluate_info_bar(main_ctx),
          status_rows:    builder.evaluate_status_rows(main_ctx),
          shortcuts_hint: builder.shortcuts_hint_text
        )
        Cclikesh::Chrome.tick_spinner(Cclikesh::Context.state[:phase]) rescue nil
        Curses.doupdate rescue nil
        Cclikesh::Runner.park_cursor_on_prompt_row
        nil
      end
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
      in [:state_set, key, value]
        Cclikesh::Context.state_set(key, value)
      in [:state_get_request, reply_to, key]
        reply_to.send([:state_get_reply, Cclikesh::Context.state[key]])
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
