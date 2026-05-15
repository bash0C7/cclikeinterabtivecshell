# frozen_string_literal: true

require "time"

module Cclikesh
  module LayoutDiag
    def self.log(tag)
      path = ENV["CCLIKESH_LAYOUT_DIAG"]
      return if path.nil? || path.empty?

      lines  = (defined?(Curses) ? (Curses.lines rescue nil) : nil)
      cols   = (defined?(Curses) ? (Curses.cols  rescue nil) : nil)
      maxyx  = begin
        (defined?(Curses) && Curses.respond_to?(:stdscr) && Curses.stdscr) ? Curses.stdscr.maxyx : nil
      rescue StandardError
        nil
      end
      winsz  = begin
        require "io/console"
        c = IO.console
        c ? c.winsize : nil
      rescue StandardError
        nil
      end
      env_l  = ENV["LINES"]
      env_c  = ENV["COLUMNS"]
      File.open(path, "a") do |f|
        f.puts "[#{Time.now.iso8601(3)}] #{tag} curses.lines=#{lines.inspect} curses.cols=#{cols.inspect} maxyx=#{maxyx.inspect} winsize=#{winsz.inspect} env_lines=#{env_l.inspect} env_cols=#{env_c.inspect}"
      end
    rescue StandardError
      # Best-effort debug instrumentation: must NEVER raise from runtime code.
      # The contract for this module IS "best effort, debug-only", so the
      # blanket rescue is by design.
      nil
    end
  end
end
