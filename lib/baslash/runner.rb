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

      # Per-line prompt: render the full prompt only on the first line of
      # a multi-line edit buffer (shift+enter continuation). Continuation
      # rows get an empty prefix so the prompt doesn't repeat. Re-evaluates
      # compose_prompt each render so cwd-dependent prefixes stay live.
      Reline.prompt_proc = ->(lines) {
        first = compose_prompt(builder, main_ctx)
        lines.each_with_index.map { |_, i| i.zero? ? first : "" }
      }

      builder.on_start_handlers.each do |h|
        h.call(nil)
      rescue StandardError => e
        Baslash::Context.logger.error("on_start handler failed: #{e.class}: #{e.message}")
      end

      catch(:quit) do
        loop do
          line = nil
          begin
            line = Reline.readmultiline(compose_prompt(builder, main_ctx), true) { true }
          rescue Interrupt
            RelineDialogs.drain_main_mailbox
            throw :quit if Context.quit?
            next
          end
          throw :quit if line.nil?
          throw :quit if Context.quit?
          line = line.to_s
          next if line.strip.empty?
          SlashDispatcher.handle(
            line,
            builder.slash_registry,
            on_submit: builder.on_submit_handler,
            state_refs: builder.state_refs,
            logger: builder.logger
          )
          throw :quit if Context.quit?
        end
      end

      builder.on_quit_handlers.each do |h|
        h.call(nil)
      rescue StandardError => e
        Baslash::Context.logger.error("on_quit handler failed: #{e.class}: #{e.message}")
      end
    ensure
      drain_residual_stdin
      TitleBar.restore
      builder.state_refs.each_value do |ref|
        ref.stop
      rescue StandardError => e
        logger = Baslash::Context.instance_variable_get(:@logger)
        logger.error("state_ref.stop failed: #{e.class}: #{e.message}") if logger
      end
    end

    # Belt-and-suspenders: consume any pending terminal-response bytes
    # (CPR \e[26;1R, DA1/2, etc.) that Reline may have triggered but not
    # consumed by the time we return. TTY-only — never drain when stdin
    # is piped (tests, scripts) since that would eat real input.
    def self.drain_residual_stdin
      return unless $stdin.tty?
      require "io/wait"
      while $stdin.wait_readable(0)
        $stdin.read_nonblock(1024)
      end
    rescue IO::WaitReadable, EOFError, Errno::EAGAIN
      # No more data available — expected terminal state after draining.
    rescue StandardError => e
      logger = Baslash::Context.instance_variable_get(:@logger)
      logger.error("stdin drain failed: #{e.class}: #{e.message}") if logger
    end

    # Default prompt: bold cyan "> " for emphasis. Kept as a simple
    # default-arg form for backward compatibility with tests and callers
    # that don't need a dynamic prefix. New code paths should call
    # compose_prompt(builder, main_ctx) so the user's prompt_prefix block
    # is honored.
    def self.prompt_text(builder, main_ctx = nil)
      return compose_prompt(builder, main_ctx) if main_ctx
      "\e[1;36m> \e[0m"
    end

    # Compose the actual prompt string each iteration, consulting the
    # builder's prompt_prefix block (if any). The block runs on the main
    # thread with a MainCtx so it can read shareable_ref state.
    def self.compose_prompt(builder, main_ctx)
      prefix = builder.evaluate_prompt_prefix(main_ctx)
      if prefix && !prefix.to_s.empty?
        "\e[1;36m#{prefix} > \e[0m"
      else
        "\e[1;36m> \e[0m"
      end
    end

    def self.install_completion(builder)
      registry = builder.slash_registry
      default_proc = ->(target) {
        return [] unless target.is_a?(String) && target.start_with?("/")
        prefix = target[1..]
        registry.slash_menu_items_starting_with(prefix).map { |item| item[:name] }
      }
      Reline.completion_proc = builder.on_tab_handler || default_proc
    end
  end
end
