# frozen_string_literal: true

require "rinda/tuplespace"
require_relative "style"

module Cclikesh
  class Renderer
    def initialize(tuple_space, output_io, registry: nil)
      @ts = tuple_space
      @out = output_io
      @registry = registry
    end

    # Drain all currently-queued render tuples and write them to output.
    # Non-blocking: take(pattern, 0) raises Rinda::RequestExpiredError when
    # no matching tuple exists, which we use as the loop terminator.
    # Rinda::TupleSpace#take returns matching tuples in LIFO order, so we
    # collect everything and process in write-order via reverse_each.
    def render_pending
      collected = []
      loop do
        collected << @ts.take([:render, nil, nil, nil], 0)
      end
    rescue Rinda::RequestExpiredError
      collected.reverse_each { |t| process(t) }
    end

    private

    def process(tuple)
      _, op, payload, opts = tuple
      case op
      when :display_append
        prefix = (opts && opts[:prompt]) || ""
        style_name = opts && opts[:style]
        styled = Style.wrap(payload, style_name, custom: resolve_custom_style(style_name))
        @out.puts("#{prefix}#{styled}")
      end
    end

    def resolve_custom_style(name)
      return nil if name.nil? || Style::BUILTINS.key?(name.to_sym)
      return nil unless @registry
      @registry.style_definition(name)
    end
  end
end
