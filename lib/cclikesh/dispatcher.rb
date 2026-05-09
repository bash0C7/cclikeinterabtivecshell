# frozen_string_literal: true

module Cclikesh
  class Dispatcher
    def initialize(tuple_space, registry, context)
      @ts = tuple_space
      @registry = registry
      @ctx = context
    end

    def dispatch_one
      _, payload = @ts.take([:key, nil])
      return :quit if payload.nil?

      if payload.start_with?("/")
        dispatch_slash(payload)
      else
        @registry.dispatch_submit(payload, @ctx)
      end
      nil
    end

    private

    def dispatch_slash(payload)
      name_part, *args = payload[1..].split(/\s+/)
      name = name_part.to_sym
      result = @registry.dispatch_slash(name, args, @ctx)
      if result == :not_registered
        @ctx.display.append("/#{name}: not registered", style: :error)
      end
    end
  end
end
