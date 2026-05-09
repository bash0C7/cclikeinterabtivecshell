# frozen_string_literal: true

require "rinda/tuplespace"

module Cclikesh
  class Renderer
    def initialize(tuple_space, output_io)
      @ts = tuple_space
      @out = output_io
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
        @out.puts("#{prefix}#{payload}")
      end
    end
  end
end
