# frozen_string_literal: true

require "drb/drb"
require_relative "live_slot"

module Cclikesh
  class Display
    include DRb::DRbUndumped

    def initialize(tuple_space)
      @ts = tuple_space
      @slot_counter = 0
      @active_slot = nil
      @mutex = Mutex.new
      @indent_first = nil
      @indent_rest  = nil
      @indent_used  = false
    end

    def append(text, style: nil, prompt: nil)
      text = apply_indent(text)
      opts = {}
      opts[:style] = style if style
      opts[:prompt] = prompt if prompt
      @ts.write([:render, :display_append, text, opts])
    end

    def begin_indent_block(first:, rest:)
      @indent_first = first
      @indent_rest  = rest
      @indent_used  = false
    end

    def end_indent_block
      @indent_first = nil
      @indent_rest  = nil
      @indent_used  = false
    end

    def open_live(style: nil, &block)
      slot = @mutex.synchronize do
        @active_slot.commit if @active_slot && @active_slot.open?
        @slot_counter += 1
        id = @slot_counter
        @ts.write([:render, :live_open, id, { style: style }])
        @active_slot = LiveSlot.new(@ts, id, style: style)
      end
      return slot unless block

      committed = false
      begin
        block.call(slot)
        slot.commit
        committed = true
      ensure
        slot.discard unless committed
      end
      slot
    end

    private

    def apply_indent(text)
      return text unless @indent_first
      if @indent_used
        "#{@indent_rest}#{text}"
      else
        @indent_used = true
        "#{@indent_first}#{text}"
      end
    end
  end
end
