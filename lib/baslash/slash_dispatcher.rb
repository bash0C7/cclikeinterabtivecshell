# frozen_string_literal: true

require_relative "ctx_proxy"
require_relative "handler_ractor"

module Baslash
  module SlashDispatcher
    def self.handle(line, registry, main_ractor, on_submit:, state_refs:)
      bp = CtxProxy.blueprint(main_ractor, state_refs)
      if line.start_with?("/")
        name, *args = line[1..].split
        entry = registry.lookup(name)
        if entry.nil?
          main_ractor.send([:append, "Unknown command: /#{name}".freeze, { style: :error }.freeze])
          return
        end
        HandlerRactor.spawn(body: entry[:body], args: args.map(&:freeze).freeze, ctx_blueprint: bp)
      else
        return unless on_submit
        HandlerRactor.spawn(body: on_submit, args: [line.freeze].freeze, ctx_blueprint: bp)
      end
    end
  end
end
