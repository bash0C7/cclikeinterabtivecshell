require "reline"
require_relative "reline_idle_patch"
require_relative "default_commands"
require_relative "debug_commands"

Warning[:experimental] = false # suppress "Ractor API is experimental" on every spawn

module Cclikesh
  module Runner
    def self.run(builder)
      terminal_setup
      Style.init!
      Chrome.init
      Display.init
      Context.init(logger: builder.logger)
      if defined?(Cclikesh::DebugEndpoint)
        Cclikesh::DebugEndpoint.start_if_enabled(builder)
      end

      install_completion(builder)
      RelineDialogs.install(builder)
      DefaultCommands.register(builder.slash_registry)
      if builder.debug_commands_enabled? || ENV["CCLIKESH_DEBUG"]
        Cclikesh::DebugCommands.register(
          builder.slash_registry,
          tick_counter: Cclikesh::RelineIdlePatch
        )
      end
      main_ctx = MainCtx.new(builder.state_refs)
      builder.header_lines.each { |line| Display.append(line) }

      Cclikesh::RelineIdlePatch.callback = lambda do
        RelineDialogs.run_chrome_tick(builder, main_ctx)
      rescue StandardError => e
        Cclikesh::Context.logger.error("chrome tick failed: #{e.class}: #{e.message}")
        nil
      end

      builder.on_start_handlers.each { |h| h.call(nil) rescue nil }

      catch(:quit) do
        loop do
          line = nil
          $stdout.write("\r\n")  # status_line placeholder row
          Cclikesh::Chrome.print_pre_prompt_divider
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
          unless line.strip.empty?
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
          # Drain any handler-emitted output (ctx_proxy → mailbox) before closing the
          # turn with chrome, so the command's output appears between prompt and
          # footer, not after footer.
          begin
            RelineDialogs.drain_main_mailbox
            throw :quit if Context.quit?
            Cclikesh::Chrome.print_post_prompt_chrome(
              status_rows:    builder.evaluate_status_rows(main_ctx),
              shortcuts_hint: builder.shortcuts_hint_text
            )
          rescue Interrupt
            RelineDialogs.drain_main_mailbox
            throw :quit if Context.quit?
          end
        end
      end

      builder.on_quit_handlers.each { |h| h.call(nil) rescue nil }
    ensure
      Cclikesh::RelineIdlePatch.callback = nil
      terminal_teardown
      builder.state_refs.each_value { |ref| ref.stop rescue nil }
    end

    def self.terminal_setup
      $stdout.write("\e[>4;2m")
      $stdout.flush
    end

    def self.terminal_teardown
      drain_stdin_residue
      $stdout.write("\e[>4;0m\e[?25h\e[m")
      $stdout.flush
    rescue StandardError => e
      warn "terminal_teardown: #{e.class}: #{e.message}"
    end

    def self.drain_stdin_residue
      return unless $stdin.respond_to?(:read_nonblock)
      8.times do
        ready, = IO.select([$stdin], nil, nil, 0.02)
        break unless ready
        $stdin.read_nonblock(4096)
      end
    rescue IO::WaitReadable, EOFError, Errno::EBADF
      nil
    end

    def self.prompt_text(_builder)
      "> "
    end

    def self.park_cursor_on_prompt_row
      nil
    end

    def self.install_completion(builder)
      return unless builder.on_tab_handler
      Reline.completion_proc = builder.on_tab_handler
    end
  end
end
