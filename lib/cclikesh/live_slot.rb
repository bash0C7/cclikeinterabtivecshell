# frozen_string_literal: true

require "drb/drb"

module Cclikesh
  class LiveSlot
    include DRb::DRbUndumped

    attr_reader :id, :style

    def initialize(tuple_space, id, style: nil)
      @ts = tuple_space
      @id = id
      @style = style
      @state = :open
      @mutex = Mutex.new
    end

    def update(text)
      @mutex.synchronize do
        return unless @state == :open
        @ts.write([:render, :live_update, @id, text])
      end
    end

    def commit
      @mutex.synchronize do
        return unless @state == :open
        @state = :committed
        @ts.write([:render, :live_commit, @id, nil])
      end
    end

    def commit_as(final_text)
      @mutex.synchronize do
        return unless @state == :open
        @state = :committed
        @ts.write([:render, :live_commit, @id, final_text])
      end
    end

    def discard
      @mutex.synchronize do
        return unless @state == :open
        @state = :discarded
        @ts.write([:render, :live_discard, @id, nil])
      end
    end

    def open?
      @mutex.synchronize { @state == :open }
    end
  end
end
