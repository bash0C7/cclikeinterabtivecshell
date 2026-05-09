# frozen_string_literal: true

require "reline"

module Cclikesh
  module RelineDialogs
    SLASH_NAME_PAD = 16

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

    def self.install(registry, ctx)
      Reline.add_dialog_proc(:autocomplete, slash_menu_dialog_proc(registry), Reline::DEFAULT_DIALOG_CONTEXT)
      Reline.add_dialog_proc(:ghost_text, ghost_text_dialog_proc(registry, ctx), Reline::DEFAULT_DIALOG_CONTEXT)
    end
  end
end
