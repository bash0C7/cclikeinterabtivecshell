# frozen_string_literal: true

require_relative "ctx_proxy"

module Baslash
  module HandlerRactor
    def self.spawn(body:, args:, ctx_blueprint:)
      Ractor.new(body, args, ctx_blueprint) do |b, a, bp|
        ctx = Baslash::CtxProxy.from_blueprint(bp)
        begin
          b.call(a, ctx)
        rescue => e
          ctx.display.append("#{e.class}: #{e.message}", style: :error)
          ctx.logger.error("handler error: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
