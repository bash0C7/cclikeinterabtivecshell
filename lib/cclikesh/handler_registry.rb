# frozen_string_literal: true

require "drb/drb"
require_relative "info_bar"
require_relative "footer"

module Cclikesh
  class HandlerRegistry
    include DRb::DRbUndumped

    def initialize(builder)
      @builder = builder
    end

    def dispatch_submit(line, ctx)
      log = @builder.logger

      @builder.before_submit_handlers.each do |h|
        begin
          h.call(line, ctx)
        rescue => e
          log.error("before_submit error: #{e.full_message}")
          break
        end
      end

      if (main = @builder.on_submit_handler)
        begin
          main.call(line, ctx)
        rescue => e
          log.error("on_submit error: #{e.full_message}")
        end
      end

      @builder.after_submit_handlers.each do |h|
        begin
          h.call(line, ctx)
        rescue => e
          log.error("after_submit error: #{e.full_message}")
          break
        end
      end
      nil
    end

    def dispatch_slash(name, args, ctx)
      handler = @builder.slash_handler(name)
      return :not_registered unless handler

      args_str = Array(args).join(" ")
      label = args_str.empty? ? "▌ /#{name}" : "▌ /#{name} #{args_str}"
      ctx.display.append(label, style: :slash_tag)
      ctx.display.begin_indent_block(first: "  └ ", rest: "    ")
      begin
        handler.call(args, ctx)
      ensure
        ctx.display.end_indent_block
      end
      nil
    end

    def dispatch_state_change(key, old, new_v, ctx)
      log = @builder.logger
      handler = @builder.on_state_change_handler
      return nil unless handler
      begin
        handler.call(key, old, new_v, ctx)
        nil
      rescue => e
        log.error("on_state_change error: #{e.full_message}")
        nil
      end
    end

    def dispatch_start(ctx)
      log = @builder.logger
      @builder.on_start_handlers.each do |h|
        begin
          h.call(ctx)
        rescue => e
          log.error("on_start error: #{e.full_message}")
        end
      end
      nil
    end

    def dispatch_quit(ctx)
      log = @builder.logger
      @builder.on_quit_handlers.reverse_each do |h|
        begin
          h.call(ctx)
        rescue => e
          log.error("on_quit error: #{e.full_message}")
        end
      end
      nil
    end

    def dispatch_tab(buf, pos, ctx)
      log = @builder.logger

      @builder.before_tab_handlers.each do |h|
        begin
          h.call(buf, pos, ctx)
        rescue => e
          log.error("before_tab error: #{e.full_message}")
          break
        end
      end

      candidates = []
      if (handler = @builder.on_tab_handler)
        begin
          result = handler.call(buf, pos, ctx)
          candidates = result.is_a?(Array) ? result : []
        rescue => e
          log.error("on_tab error: #{e.full_message}")
        end
      end

      @builder.after_tab_handlers.each do |h|
        begin
          h.call(buf, pos, candidates, ctx)
        rescue => e
          log.error("after_tab error: #{e.full_message}")
          break
        end
      end

      candidates
    end

    def snapshot_info_bar(ctx)
      log = @builder.logger

      label = compute_spinner_label(ctx, log)
      frame = label ? next_spinner_frame : nil
      segments = compute_info_segments(ctx, log)

      { spinner_frame: frame, spinner_label: label, segments: segments }
    end

    def slash_names_starting_with(prefix)
      @builder.slash_handlers.keys
        .map(&:to_s)
        .select { |n| n.start_with?(prefix) }
        .sort
        .map { |n| "/#{n}" }
    end

    def current_prompt_suggestion(ctx)
      block = @builder.prompt_suggestion_block
      return nil unless block
      result = block.call(ctx)
      result.nil? || result.to_s.empty? ? nil : result.to_s
    rescue StandardError => e
      @builder.logger.error("prompt_suggestion error: #{e.full_message}")
      nil
    end

    def slash_menu_items_starting_with(prefix)
      @builder.slash_handlers.keys
        .map(&:to_s)
        .select { |n| n.start_with?(prefix) }
        .sort
        .map { |n| { name: "/#{n}", description: @builder.slash_description(n.to_sym) } }
    end

    def style_definition(name)
      @builder.style_definition(name)
    end

    def tick_interval
      @builder.tick_interval
    end

    def logger
      @builder.logger
    end

    def editor_mode
      @builder.editor_mode
    end

    def header_lines
      cfg = @builder.header_config
      cfg ? cfg.lines : []
    end

    def header_height
      cfg = @builder.header_config
      cfg ? cfg.height : 0
    end

    def footer_height
      1 + @builder.status_rows.size
    end

    def snapshot_status_rows(ctx)
      log = @builder.logger
      rows = []
      @builder.status_rows.each do |name, _order, block|
        row = Footer::Row.new
        begin
          block.call(row, ctx)
          rows << row.to_line
        rescue => e
          log.error("status_row(:#{name}) error: #{e.full_message}")
        end
      end
      rows
    end

    def snapshot_footer(ctx)
      info_snap = snapshot_info_bar(ctx)
      info_line = InfoBar.compose(
        spinner_frame: info_snap[:spinner_frame],
        spinner_label: info_snap[:spinner_label],
        segments:      info_snap[:segments]
      )
      [info_line] + snapshot_status_rows(ctx)
    end

    private

    def compute_spinner_label(ctx, log)
      proc_obj = @builder.spinner_label_proc
      return nil unless proc_obj
      begin
        result = proc_obj.call(ctx)
      rescue => e
        log.error("spinner_label error: #{e.full_message}")
        return nil
      end
      case result
      when nil   then nil
      when :auto then next_idle_phrase
      else result.to_s
      end
    end

    def next_spinner_frame
      frames = @builder.spinner_frames
      return nil if frames.nil? || frames.empty?
      @spinner_idx = ((@spinner_idx || -1) + 1) % frames.size
      frames[@spinner_idx]
    end

    def next_idle_phrase
      phrases = @builder.idle_phrases
      return nil if phrases.nil? || phrases.empty?
      @idle_idx = ((@idle_idx || -1) + 1) % phrases.size
      phrases[@idle_idx]
    end

    def compute_info_segments(ctx, log)
      out = []
      @builder.info_segments.each do |name, _order, block|
        begin
          value = block.call(ctx)
        rescue => e
          log.error("info(:#{name}) error: #{e.full_message}")
          next
        end
        next if value.nil? || value.to_s.empty?
        out << value.to_s
      end
      out
    end
  end
end
