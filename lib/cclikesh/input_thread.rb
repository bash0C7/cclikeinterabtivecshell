# frozen_string_literal: true

require "reline"
require_relative "layout"

module Cclikesh
  class InputThread
    def self.install_completion_proc(registry:, ctx:, apply: nil)
      proc = ->(buf) {
        if buf.start_with?("/") && !buf.include?(" ")
          registry.slash_names_starting_with(buf[1..])
        elsif (m = buf.match(/\A(.*)@(\S*)\z/m))
          file_path_candidates(m[1], m[2])
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
          payload = line.nil? ? nil : line.chomp
          ts.write([:key, payload])
          break if payload.nil?
        end
      end
    end

    def self.park_cursor_in_input
      return unless $stdout.tty?
      Layout.position($stdout, Layout.input_top)
      Layout.clear_line($stdout)
      $stdout.flush
    end

    def self.enable_autocompletion
      Reline.autocompletion = true if Reline.respond_to?(:autocompletion=)
    rescue StandardError
      # older Reline; fall back to no autocompletion popup
    end
  end
end
