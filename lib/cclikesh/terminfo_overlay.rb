# frozen_string_literal: true

require "digest"

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

      private

      # Returns the infocmp -1 output for `term` as a String, or nil if
      # the command is missing, fails, or produces empty output.
      def read_terminfo_source(term)
        out = nil
        IO.popen(["infocmp", "-1", term, { err: :close }], "r") do |io|
          out = io.read
        end
        return nil if out.nil? || out.strip.empty?
        out
      rescue Errno::ENOENT, Errno::EPIPE, Errno::EACCES
        nil
      end

      # Returns `source` with any line matching ^\s*(smcup|rmcup)= removed.
      # Pure function: no I/O, no ENV access. Assumes one capability per
      # line (the `infocmp -1` format); folded/continued-line input is not
      # supported and would silently miss a smcup on a wrapped line.
      def strip_smcup_rmcup(source)
        source.each_line.reject { |l| l =~ /^\s*(smcup|rmcup)=/ }.join
      end

      # Returns `source` with the first non-comment, non-blank line
      # (the terminfo entry header `name|alias|...,`) replaced by
      # `<new_name>|<original first alias or name> without smcup,`.
      def rename_entry(source, new_name)
        lines = source.lines
        idx = lines.index { |l| !l.start_with?("#") && !l.strip.empty? }
        return source unless idx
        original_first = lines[idx].split("|", 2).first.strip
        lines[idx] = "#{new_name}|#{original_first} without smcup,\n"
        lines.join
      end

      # Stable short digest of the stripped+renamed source. Used to key
      # the on-disk compile cache so terminfo changes invalidate it.
      def digest_of(source)
        Digest::SHA1.hexdigest(source)[0, 16]
      end
    end
  end
end
