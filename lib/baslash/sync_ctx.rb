# frozen_string_literal: true

require_relative "display"
require_relative "context"

module Baslash
  # Main-thread synchronous execution context for slash command and
  # on_submit handlers. Mirrors the public API of CtxProxy but talks to
  # Display, Context, and ShareableRef directly without Ractor message
  # passing. Used when handlers run on the main thread between Reline
  # prompts (default mode); CtxProxy/HandlerRactor remain available for
  # explicit background execution.
  class SyncCtx
    def initialize(state_refs:, logger:)
      @state_refs = state_refs
      @logger     = logger
      @display    = DisplayProxy.new
      @state      = StateProxy.new
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

    def shareable(name)
      ref = @state_refs[name.to_sym]
      raise ArgumentError, "no shareable_ref named #{name.inspect}" if ref.nil?
      ShareableProxy.new(ref)
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

    class ShareableProxy
      def initialize(ref)
        @ref = ref
      end

      def call(method, *args)
        @ref.call(method, *args)
      end
    end
  end
end
