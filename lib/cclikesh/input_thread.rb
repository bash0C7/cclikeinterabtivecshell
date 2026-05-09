# frozen_string_literal: true

require "reline"

module Cclikesh
  class InputThread
    def self.install_completion_proc(registry:, ctx:, apply: ->(p) { Reline.completion_proc = p })
      proc = ->(buf) {
        registry.dispatch_tab(buf, buf.bytesize, ctx)
      }
      apply.call(proc)
      proc
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

          line = reader.call(prompt)
          payload = line.nil? ? nil : line.chomp
          ts.write([:key, payload])
          break if payload.nil?
        end
      end
    end
  end
end
