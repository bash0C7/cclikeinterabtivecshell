# frozen_string_literal: true

module Cclikesh
  class Renderer
    def initialize(tuple_space, output_io)
      @ts = tuple_space
      @out = output_io
    end

    # Drain all currently-queued render tuples and write them to output.
    # Non-blocking: uses try_take to pull tuples until the queue is empty.
    # The underlying tuple space (Rinda via ts4r) returns matching tuples
    # in LIFO order, so we collect everything and process in reverse to
    # restore write order.
    def render_pending
      collected = []
      loop do
        tuple = @ts.try_take([:render, nil, nil, nil])
        break if tuple.nil?
        collected << tuple
      end
      collected.reverse_each { |t| process(t) }
    end

    private

    def process(tuple)
      _, op, payload, opts = tuple
      case op
      when :display_append
        prefix = (opts && opts[:prompt]) || ""
        @out.puts("#{prefix}#{payload}")
      end
    end
  end
end
