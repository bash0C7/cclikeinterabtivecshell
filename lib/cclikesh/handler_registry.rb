# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class HandlerRegistry
    include DRb::DRbUndumped

    def initialize(builder)
      @builder = builder
    end

    def dispatch_submit(line, ctx)
      log = @builder.logger

      @builder.before_submit_handlers.each do |h|
        begin
          h.call(line, ctx)
        rescue => e
          log.error("before_submit error: #{e.full_message}")
          break
        end
      end

      if (main = @builder.on_submit_handler)
        begin
          main.call(line, ctx)
        rescue => e
          log.error("on_submit error: #{e.full_message}")
        end
      end

      @builder.after_submit_handlers.each do |h|
        begin
          h.call(line, ctx)
        rescue => e
          log.error("after_submit error: #{e.full_message}")
          break
        end
      end
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

    def dispatch_start(ctx)
      log = @builder.logger
      @builder.on_start_handlers.each do |h|
        begin
          h.call(ctx)
        rescue => e
          log.error("on_start error: #{e.full_message}")
        end
      end
      nil
    end

    def dispatch_quit(ctx)
      log = @builder.logger
      @builder.on_quit_handlers.reverse_each do |h|
        begin
          h.call(ctx)
        rescue => e
          log.error("on_quit error: #{e.full_message}")
        end
      end
      nil
    end

    def dispatch_tab(buf, pos, ctx)
      log = @builder.logger
      handler = @builder.on_tab_handler
      return [] unless handler
      begin
        result = handler.call(buf, pos, ctx)
        result.is_a?(Array) ? result : []
      rescue => e
        log.error("on_tab error: #{e.full_message}")
        []
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
