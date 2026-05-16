# frozen_string_literal: true

require_relative "sync_ctx"
require_relative "display"

module Baslash
  module SlashDispatcher
    def self.handle(line, registry, on_submit:, state_refs:, logger:)
      ctx = SyncCtx.new(state_refs: state_refs, logger: logger)
      if line.start_with?("/")
        name, *args = line[1..].split
        return if name.nil? || name.empty?
        entry = registry.lookup(name)
        if entry.nil?
          Baslash::Display.append("Unknown command: /#{name}", style: :error)
          return
        end
        entry[:body].call(args.freeze, ctx)
      else
        return unless on_submit
        on_submit.call([line.freeze].freeze, ctx)
      end
    rescue Interrupt
      Baslash::Display.append("^C", style: :dim)
      logger.info("handler interrupted by SIGINT") if logger.respond_to?(:info)
    rescue StandardError => e
      Baslash::Display.append("Handler failed: #{e.class}: #{e.message}", style: :error)
      logger.error("handler failed: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}") if logger.respond_to?(:error)
    end
  end
end
