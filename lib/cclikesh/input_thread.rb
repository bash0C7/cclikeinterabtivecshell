# frozen_string_literal: true

require "reline"
require_relative "info_bar"

module Cclikesh
  class InputThread
    def self.install_completion_proc(registry:, ctx:, apply: ->(p) { Reline.completion_proc = p })
      proc = ->(buf) {
        if buf.start_with?("/") && !buf.include?(" ")
          registry.slash_names_starting_with(buf[1..])
        else
          registry.dispatch_tab(buf, buf.bytesize, ctx)
        end
      }
      apply.call(proc)
      proc
    end

    def self.compose_prompt(base_prompt, registry, ctx)
      return base_prompt if registry.nil?
      snap = registry.snapshot_info_bar(ctx)
      bar = InfoBar.compose(
        spinner_frame: snap[:spinner_frame],
        spinner_label: snap[:spinner_label],
        segments:      snap[:segments]
      )
      bar.empty? ? base_prompt : "#{bar}\n#{base_prompt}"
    end

    def self.start(ts, reader:, prompt: "> ", registry: nil, ctx: nil)
      install_completion_proc(registry: registry, ctx: ctx) if registry && ctx

      Thread.new do
        loop do
          quit_tuple = begin
            ts.read([:cmd, :quit], 0)
          rescue Rinda::RequestExpiredError
            nil
          end
          break if quit_tuple

          effective_prompt = compose_prompt(prompt, registry, ctx)
          line = reader.call(effective_prompt)
          payload = line.nil? ? nil : line.chomp
          ts.write([:key, payload])
          break if payload.nil?
        end
      end
    end
  end
end
