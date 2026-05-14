require "curses"
require "reline"
require_relative "reline_idle_patch"
require_relative "default_commands"
require_relative "debug_commands"
require_relative "terminfo_overlay"

Warning[:experimental] = false # suppress "Ractor API is experimental" on every spawn

module Cclikesh
  module Runner
    def self.run(builder)
      # Defence-in-depth: Cclikesh.run normally calls this first so the
      # mutation is in place before user code in the builder block can
      # trigger an implicit Curses init. The call here covers direct
      # Runner.run invocations (tests, future embedders).
      TerminfoOverlay.install_if_possible
      init_curses
      Style.init!
      Chrome.init
      Signal.trap("WINCH") { Chrome.winsize_dirty = true }
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
      # /help must be registered AFTER all other commands so its frozen
      # snapshot of the registry sees them all. Cannot be merged into
      # DefaultCommands.register above for the same reason.
      DefaultCommands.register_help(builder.slash_registry)
      main_ctx = MainCtx.new(builder.state_refs)
      # Header lines now live inside the body as regular append-only
      # output, so they scroll with the rest of the transcript.
      builder.header_lines.each { |line| Display.append(line) }
      Chrome.update_footer(
        info_bar:        builder.evaluate_info_bar(main_ctx),
        status_rows:     builder.evaluate_status_rows(main_ctx),
        shortcuts_hint:  builder.shortcuts_hint_text
      )
      Curses.doupdate
      park_cursor_on_prompt_row

      # Run the same chrome repaint that Reline's periodic_tick uses,
      # but call it from inside Reline::ANSI#inner_getc's 10ms poll
      # loop (see reline_idle_patch.rb). This lets the footer/spinner
      # animate while the user is idle and while a handler Ractor is
      # busy on a long-running command, without spawning any Thread
      # (which is forbidden by test/test_thread_zero.rb).
      Cclikesh::RelineIdlePatch.callback = lambda do
        if Chrome.winsize_dirty
          Chrome.winsize_dirty = false
          begin
            Chrome.handle_resize
          rescue StandardError => e
            Cclikesh::Context.logger.error("winsize resize failed: #{e.class}: #{e.message}") rescue nil
          end
        end
        RelineDialogs.run_chrome_tick(builder, main_ctx)
      rescue StandardError => e
        # The tick fires from inside Reline's input loop — letting an
        # exception escape would crash the whole shell. Log + continue,
        # so a broken info block doesn't blow up the prompt.
        Cclikesh::Context.logger.error("chrome tick failed: #{e.class}: #{e.message}") rescue nil
        nil
      end

      builder.on_start_handlers.each { |h| h.call(nil) rescue nil }

      catch(:quit) do
        loop do
          park_cursor_on_prompt_row
          line = nil
          begin
            # readmultiline with an always-true confirmation block: Enter
            # alone always submits, while Shift+Enter (bound to key_newline
            # in RelineDialogs.install) inserts a literal newline into the
            # buffer without ending the readline call.
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

      builder.on_quit_handlers.each { |h| h.call(nil) rescue nil }
    ensure
      Cclikesh::RelineIdlePatch.callback = nil
      teardown_curses
      builder.state_refs.each_value { |ref| ref.stop rescue nil }
    end

    def self.init_curses
      Curses.init_screen
      Curses.cbreak
      Curses.noecho
      Curses.start_color
      Curses.use_default_colors
      Curses.stdscr.keypad(true)
      # xterm "modifyOtherKeys" mode 2: ask the terminal to encode
      # modifier+key combinations as CSI 27;<mods>;<code>~ so we can
      # distinguish Shift+Enter (\e[27;2;13~) from plain Enter (\r).
      # Combined with the keymap added in RelineDialogs.install, this
      # gives Claude Code's prompt behavior: Enter submits, Shift+Enter
      # inserts a newline.
      $stdout.print("\e[>4;2m")
      $stdout.flush
    end

    def self.teardown_curses
      begin
        Signal.trap("WINCH", "DEFAULT")
      rescue ArgumentError, Errno::EINVAL => e
        # Best-effort: restore may fail on exotic platforms; log and proceed.
        Cclikesh::Context.logger.error("trap restore failed: #{e.class}: #{e.message}") rescue nil
      end
      # Drain any pending DSR/CPR responses Reline queried but didn't read,
      # otherwise they leak as literal characters into the next shell prompt.
      drain_stdin_residue
      # Explicitly emit terminal-restore sequences before redirecting stdout:
      #   \e[>4;0m   -- disable xterm modifyOtherKeys (paired with init)
      #   \e[?1049l  -- exit alt-screen back to main buffer
      #   \e[r       -- reset scroll region to full screen
      #   \e[?25h    -- show cursor
      #   \e[m       -- reset SGR (colors/attrs)
      # Some terminals (ghostty on macOS) don't see ncurses' own restore
      # escapes from close_screen reliably, so do it ourselves first.
      # \e[?1049l is the rmcup pair to \e[?1049h (smcup). If
      # TerminfoOverlay.installed? is true, curses never emitted
      # smcup (the terminfo entry has neither cap), so emitting
      # rmcup here would have no buffer to leave — harmless, but
      # noise. Skip it to keep the teardown bytes clean.
      tail = TerminfoOverlay.installed? ? "" : "\e[?1049l"
      $stdout.print("\e[>4;0m#{tail}\e[r\e[?25h\e[m")
      $stdout.flush
      # Redirect stdout to /dev/null before close_screen so that ncurses'
      # terminal-restore writes don't block on an unread PTY (e.g. in tests).
      $stdout.reopen("/dev/null", "w") rescue nil
      STDOUT.reopen("/dev/null", "w") rescue nil
      Curses.close_screen
    rescue
      nil
    end

    # Consume any pending DSR/CPR responses (`^[[…R`) Reline queried but
    # didn't read, otherwise they leak as literal characters into the
    # next shell prompt.  Capped at a small number of reads so a chatty
    # PTY (e.g. in tests) cannot cause an infinite loop here.
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

    # Push the terminal cursor to the row reserved for Reline's prompt.
    # With dividers in place the prompt sits two rows above the footer top
    # (divider-above-footer occupies the row between prompt and footer).
    # Curses leaves the cursor somewhere in a painted window; without this
    # explicit park, Reline anchors its readline UI there and overwrites
    # footer or divider content.
    def self.park_cursor_on_prompt_row
      $stdout.print("\e[#{Curses.lines - Chrome::FOOTER_HEIGHT - 1};1H")
      $stdout.flush
    end

    def self.install_completion(builder)
      return unless builder.on_tab_handler
      Reline.completion_proc = builder.on_tab_handler
    end
  end
end
