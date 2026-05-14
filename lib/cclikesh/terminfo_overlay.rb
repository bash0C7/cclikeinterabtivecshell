# frozen_string_literal: true

module Cclikesh
  # Strips smcup/rmcup from the user's terminfo entry at startup so that
  # Curses.init_screen does not enter the alt-screen buffer. This preserves
  # the terminal's native scrollback while keeping the rest of the curses
  # surface intact. Falls back to a no-op (curses runs in normal alt-screen
  # mode) when infocmp/tic are unavailable or the entry cannot be processed.
  module TerminfoOverlay
    @installed = false

    class << self
      # True iff a previous install_if_possible call successfully replaced
      # ENV["TERM"] / ENV["TERMINFO_DIRS"]. Runner.teardown_curses consults
      # this to decide whether to emit \e[?1049l (only needed when curses
      # actually entered alt-screen, i.e. when install_if_possible failed).
      def installed?
        @installed
      end

      # Idempotent install. Returns true on success, false on any skip path.
      # Never raises — caller may rely on the curses init path either way.
      def install_if_possible
        term = ENV["TERM"].to_s
        return false if term.empty?
        return false if term == "dumb"
        # Full implementation arrives in later tasks.
        false
      end

      # Test-only: clear @installed so tests can re-exercise the install
      # path without process restart.
      def reset_state_for_test
        @installed = false
      end
    end
  end
end
