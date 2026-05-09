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
    end

    def append(text, style: nil, prompt: nil)
      opts = {}
      opts[:style] = style if style
      opts[:prompt] = prompt if prompt
      @ts.write([:render, :display_append, text, opts])
    end

    def open_live(style: nil)
      @mutex.synchronize do
        @active_slot.commit if @active_slot && @active_slot.open?
        @slot_counter += 1
        id = @slot_counter
        @ts.write([:render, :live_open, id, { style: style }])
        @active_slot = LiveSlot.new(@ts, id, style: style)
      end
      @active_slot
    end
  end
end
