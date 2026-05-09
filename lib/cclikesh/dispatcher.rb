# frozen_string_literal: true

require "open3"

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
      elsif payload.start_with?("!")
        dispatch_shell(payload[1..].to_s)
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

    def dispatch_shell(cmd)
      cmd = cmd.strip
      return if cmd.empty?

      @ctx.display.append("$ #{cmd}", style: :slash_tag)
      @ctx.display.begin_indent_block(first: "  ⎿  ", rest: "     ")
      begin
        out, err, status = Open3.capture3(cmd)
        out.each_line { |line| @ctx.display.append(line.chomp) } unless out.empty?
        err.each_line { |line| @ctx.display.append(line.chomp, style: :error) } unless err.empty?
        unless status.success?
          @ctx.display.append("(exit #{status.exitstatus})", style: :dim)
        end
      rescue StandardError => e
        @ctx.display.append("error: #{e.class}: #{e.message}", style: :error)
      ensure
        @ctx.display.end_indent_block
      end
    end
  end
end
