# frozen_string_literal: true

require_relative "display"
require_relative "context"
require_relative "title_bar"

module Baslash
  # Main-thread synchronous execution context for slash command and
  # on_submit handlers. Talks to Display and Context directly without
  # any Ractor message passing.
  class SyncCtx
    def initialize(logger:)
      @logger  = logger
      @display = DisplayProxy.new
      @state   = StateProxy.new
    end

    attr_reader :logger

    def display
      @display
    end

    def state
      @state
    end

    def quit
      Baslash::Context.quit
    end

    class DisplayProxy
      def append(text, style: nil)
        Baslash::Display.append(text, style: style)
      end

      def open_live(style: nil)
        sid = Baslash::Display.open_live(style: style)
        slot = LiveSlot.new(sid)
        if block_given?
          begin
            yield slot
            slot.commit unless slot.committed?
          rescue
            slot.discard
            raise
          end
        end
        slot
      end

      def dialog(content, style: nil)
        Baslash::Display.dialog(content, style: style)
      end
    end

    class LiveSlot
      def initialize(sid)
        @sid = sid
        @committed = false
      end

      def update(text)
        Baslash::Display.live_update(@sid, text.to_s)
      end

      def commit(final = nil)
        Baslash::Display.live_commit(@sid, final)
        @committed = true
      end

      def discard
        Baslash::Display.live_discard(@sid)
        @committed = true
      end

      def committed?
        @committed
      end
    end

    class StateProxy
      def []=(key, value)
        Baslash::Context.state_set(key.to_sym, value)
      end

      def [](key)
        Baslash::Context.state[key.to_sym]
      end
    end

  end
end
