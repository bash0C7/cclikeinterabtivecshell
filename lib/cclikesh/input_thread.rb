# frozen_string_literal: true

require "reline"
require_relative "layout"
require_relative "reline_dialogs"

module Cclikesh
  class InputThread
    def self.install_completion_proc(registry:, ctx:, apply: nil)
      proc = ->(buf) {
        if buf.start_with?("/") && !buf.include?(" ")
          registry.slash_names_starting_with(buf[1..])
        elsif (m = buf.match(/\A(.*)@(\S*)\z/m))
          file_path_candidates(m[1], m[2])
        elsif buf.empty?
          suggestion_or_tab(registry, ctx, buf)
        else
          registry.dispatch_tab(buf, buf.bytesize, ctx)
        end
      }
      if apply
        apply.call(proc)
      else
        Reline.completer_word_break_characters = ""
        Reline.completion_proc = proc
      end
      proc
    end

    def self.suggestion_or_tab(registry, ctx, buf)
      return registry.dispatch_tab(buf, 0, ctx) unless registry.respond_to?(:current_prompt_suggestion)
      suggestion = registry.current_prompt_suggestion(ctx)
      return [suggestion] if suggestion
      registry.dispatch_tab(buf, 0, ctx)
    end

    def self.file_path_candidates(prefix, query)
      pattern = query.empty? ? "*" : "#{query}*"
      paths = Dir.glob(pattern).select { |p| File.exist?(p) }.sort.first(50)
      paths.map { |p| "#{prefix}@#{p}" }
    rescue StandardError
      []
    end

    def self.start(ts, reader:, prompt: "> ", registry: nil, ctx: nil)
      install_completion_proc(registry: registry, ctx: ctx) if registry && ctx
      enable_autocompletion
      install_dialogs(registry, ctx) if registry && ctx
      configure_editor_mode(registry) if registry

      Thread.new do
        loop do
          quit_tuple = begin
            ts.read([:cmd, :quit], 0)
          rescue Rinda::RequestExpiredError
            nil
          end
          break if quit_tuple

          park_cursor_in_input
          line = reader.call(prompt)
          payload = normalize_payload(line)
          ts.write([:key, payload])
          break if payload.nil?
        end
      end
    end

    def self.park_cursor_in_input
      return unless $stdout.tty?
      middle_row = Layout.input_height >= 3 ? Layout.input_top + 1 : Layout.input_top
      Layout.position($stdout, middle_row)
      Layout.clear_line($stdout)
      $stdout.flush
    end

    def self.enable_autocompletion
      Reline.autocompletion = true if Reline.respond_to?(:autocompletion=)
    rescue StandardError
      # older Reline; fall back to no autocompletion popup
    end

    def self.install_dialogs(registry, ctx)
      RelineDialogs.install(registry, ctx) if Reline.respond_to?(:add_dialog_proc)
    rescue StandardError
      # older Reline lacking dialog API; degrade gracefully
    end

    def self.configure_editor_mode(registry)
      return unless registry.respond_to?(:editor_mode)
      case registry.editor_mode
      when :vim, :vi   then Reline.vi_editing_mode
      when :emacs, nil then Reline.emacs_editing_mode
      end
    rescue StandardError
      # older Reline lacking these toggles
    end

    def self.normalize_payload(raw)
      return nil if raw.nil?
      raw.gsub(/\\\n/, "\n").chomp
    end
  end
end
