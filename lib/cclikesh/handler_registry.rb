# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class HandlerRegistry
    include DRb::DRbUndumped

    def initialize(builder)
      @builder = builder
    end

    def dispatch_submit(line, ctx)
      handler = @builder.on_submit_handler
      handler.call(line, ctx) if handler
      nil
    end

    def dispatch_slash(name, args, ctx)
      handler = @builder.slash_handler(name)
      return :not_registered unless handler
      handler.call(args, ctx)
      nil
    end

    def dispatch_state_change(key, old, new_v, ctx)
      log = @builder.logger
      handler = @builder.on_state_change_handler
      return nil unless handler
      begin
        handler.call(key, old, new_v, ctx)
        nil
      rescue => e
        log.error("on_state_change error: #{e.full_message}")
        nil
      end
    end

    def style_definition(name)
      @builder.style_definition(name)
    end

    def logger
      @builder.logger
    end
  end
end
