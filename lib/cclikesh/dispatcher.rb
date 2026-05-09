# frozen_string_literal: true

module Cclikesh
  class Dispatcher
    def initialize(tuple_space, builder, context)
      @ts = tuple_space
      @builder = builder
      @ctx = context
    end

    def dispatch_one
      _, payload = @ts.take([:key, nil])
      return :quit if payload.nil?

      if payload.start_with?("/")
        dispatch_slash(payload)
      else
        dispatch_submit(payload)
      end
      nil
    end

    private

    def dispatch_submit(line)
      @ts.write([:event, :submit, line])
      handler = @builder.on_submit_handler
      handler.call(line, @ctx) if handler
    end

    def dispatch_slash(payload)
      name_part, *args = payload[1..].split(/\s+/)
      name = name_part.to_sym
      @ts.write([:event, :slash, name, args])
      handler = @builder.slash_handler(name)
      if handler
        handler.call(args, @ctx)
      else
        @ctx.display.append("/#{name}: not registered", style: :error)
      end
    end
  end
end
