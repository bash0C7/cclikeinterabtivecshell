# frozen_string_literal: true

require "rinda/tuplespace"
require_relative "style"

module Cclikesh
  class Renderer
    def initialize(tuple_space, output_io, registry: nil)
      @ts = tuple_space
      @out = output_io
      @registry = registry
      @live_state = nil
    end

    def render_pending
      collected = []
      loop do
        collected << @ts.take([:render, nil, nil, nil], 0)
      end
    rescue Rinda::RequestExpiredError
      retry_three_arg(collected)
      collected.reverse_each { |t| process(t) }
    end

    private

    # Some live tuples have 3 fields (e.g. [:render, :live_discard, id]).
    # They won't match the 4-arity pattern above; drain them too.
    # Prepend into the front of the array so that after reverse_each they
    # are processed after the 4-arity tuples (preserving write-time order).
    def retry_three_arg(into)
      three_arg = []
      loop do
        three_arg << @ts.take([:render, nil, nil], 0)
      end
    rescue Rinda::RequestExpiredError
      into.unshift(*three_arg)
    end

    def process(tuple)
      case tuple[1]
      when :display_append
        process_display_append(tuple)
      when :live_open
        process_live_open(tuple)
      when :live_update
        process_live_update(tuple)
      when :live_commit
        process_live_commit(tuple)
      when :live_discard
        process_live_discard(tuple)
      end
    end

    def process_display_append(tuple)
      _, _, payload, opts = tuple
      prefix = (opts && opts[:prompt]) || ""
      style_name = opts && opts[:style]
      styled = Style.wrap(payload, style_name, custom: resolve_custom_style(style_name))

      if @live_state
        @out.write("\r\e[2K")
        @out.write("#{prefix}#{styled}\n")
        redraw_live
      else
        @out.puts("#{prefix}#{styled}")
      end
    end

    def process_live_open(tuple)
      _, _, id, opts = tuple
      @live_state = { id: id, style: opts && opts[:style], last_text: nil }
    end

    def process_live_update(tuple)
      _, _, id, text = tuple
      return unless @live_state && @live_state[:id] == id
      style_name = @live_state[:style]
      styled = Style.wrap(text, style_name, custom: resolve_custom_style(style_name))
      @out.write("\r\e[2K#{styled}")
      @live_state[:last_text] = text
    end

    def process_live_commit(tuple)
      _, _, id, final_text = tuple
      return unless @live_state && @live_state[:id] == id
      style_name = @live_state[:style]
      text = final_text || @live_state[:last_text] || ""
      styled = Style.wrap(text, style_name, custom: resolve_custom_style(style_name))
      @out.write("\r\e[2K#{styled}\n")
      @live_state = nil
    end

    def process_live_discard(tuple)
      _, _, id = tuple
      return unless @live_state && @live_state[:id] == id
      @out.write("\r\e[2K")
      @live_state = nil
    end

    def redraw_live
      return unless @live_state
      text = @live_state[:last_text]
      return if text.nil?
      style_name = @live_state[:style]
      styled = Style.wrap(text, style_name, custom: resolve_custom_style(style_name))
      @out.write("\r\e[2K#{styled}")
    end

    def resolve_custom_style(name)
      return nil if name.nil? || Style::BUILTINS.key?(name.to_sym)
      return nil unless @registry
      @registry.style_definition(name)
    end
  end
end
