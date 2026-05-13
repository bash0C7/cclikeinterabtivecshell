require "curses"
require "reline"

Warning[:experimental] = false # suppress "Ractor API is experimental" on every spawn

module Cclikesh
  module Runner
    def self.run(builder)
      init_curses
      Style.init!
      Chrome.init
      Display.init
      Context.init(logger: builder.logger)
      if defined?(Cclikesh::DebugEndpoint)
        Cclikesh::DebugEndpoint.start_if_enabled(builder)
      end

      install_completion(builder)
      RelineDialogs.install(builder)
      main_ctx = MainCtx.new(builder.state_refs)
      Chrome.update_header(builder.header_lines)
      Chrome.update_footer(
        info_bar:        builder.evaluate_info_bar(main_ctx),
        status_rows:     builder.evaluate_status_rows(main_ctx),
        shortcuts_hint:  builder.shortcuts_hint_text
      )
      Curses.doupdate
      park_cursor_on_prompt_row

      builder.on_start_handlers.each { |h| h.call(nil) rescue nil }

      catch(:quit) do
        loop do
          park_cursor_on_prompt_row
          line = nil
          begin
            line = Reline.readline(prompt_text(builder), true)
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
    end

    def self.teardown_curses
      # Redirect stdout to /dev/null before calling endwin so that ncurses
      # terminal-restore writes don't block on an unread PTY (e.g. in tests).
      $stdout.reopen("/dev/null", "w") rescue nil
      STDOUT.reopen("/dev/null", "w") rescue nil
      Curses.close_screen
    rescue
      nil
    end

    def self.prompt_text(_builder)
      "> "
    end

    # Push the terminal cursor to the row reserved for Reline's prompt.
    # The prompt sits just above the footer (one row above footer_win top).
    # Curses leaves the cursor at some painted footer row; without this,
    # Reline anchors its readline UI there and the user's input overwrites
    # the footer content.
    def self.park_cursor_on_prompt_row
      $stdout.print("\e[#{Curses.lines - Chrome::FOOTER_HEIGHT};1H")
      $stdout.flush
    end

    def self.install_completion(builder)
      return unless builder.on_tab_handler
      Reline.completion_proc = builder.on_tab_handler
    end
  end
end
