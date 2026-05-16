# frozen_string_literal: true

require "reline"
require_relative "default_commands"
require_relative "debug_commands"
require_relative "display"
require_relative "title_bar"
require_relative "reline_dialogs"
require_relative "context"
require_relative "main_ctx"
require_relative "slash_dispatcher"

Warning[:experimental] = false

module Baslash
  module Runner
    def self.run(builder)
      Context.init(logger: builder.logger)
      if defined?(Baslash::DebugEndpoint)
        Baslash::DebugEndpoint.start_if_enabled(builder)
      end

      install_completion(builder)
      RelineDialogs.install(builder)
      DefaultCommands.register(builder.slash_registry)
      if builder.debug_commands_enabled? || ENV["BASLASH_DEBUG"]
        Baslash::DebugCommands.register(builder.slash_registry)
      end
      DefaultCommands.register_help(builder.slash_registry)

      main_ctx = MainCtx.new(builder.state_refs)
      builder.header_lines.each { |line| Display.append(line) }
      hint = builder.shortcuts_hint_text.to_s
      Display.append(hint) unless hint.empty?
      TitleBar.tick(phase: :ready, ctx_text: RelineDialogs.compose_ctx_text(builder, main_ctx))

      builder.on_start_handlers.each do |h|
        h.call(nil)
      rescue StandardError => e
        Baslash::Context.logger.error("on_start handler failed: #{e.class}: #{e.message}")
      end

      catch(:quit) do
        loop do
          line = nil
          begin
            line = Reline.readmultiline(prompt_text(builder), true) { true }
          rescue Interrupt
            RelineDialogs.drain_main_mailbox
            throw :quit if Context.quit?
            next
          end
          throw :quit if line.nil?
          throw :quit if Context.quit?
          line = line.to_s
          next if line.strip.empty?
          begin
            SlashDispatcher.handle(
              line,
              builder.slash_registry,
              Ractor.current,
              on_submit: builder.on_submit_handler,
              state_refs: builder.state_refs
            )
          rescue Interrupt
            RelineDialogs.drain_main_mailbox
            throw :quit if Context.quit?
          end
        end
      end

      builder.on_quit_handlers.each do |h|
        h.call(nil)
      rescue StandardError => e
        Baslash::Context.logger.error("on_quit handler failed: #{e.class}: #{e.message}")
      end
    ensure
      TitleBar.restore
      builder.state_refs.each_value do |ref|
        ref.stop
      rescue StandardError => e
        logger = Baslash::Context.instance_variable_get(:@logger)
        logger.error("state_ref.stop failed: #{e.class}: #{e.message}") if logger
      end
    end

    def self.prompt_text(_builder)
      "> "
    end

    def self.install_completion(builder)
      return unless builder.on_tab_handler
      Reline.completion_proc = builder.on_tab_handler
    end
  end
end
