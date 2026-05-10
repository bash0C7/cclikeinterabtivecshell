# frozen_string_literal: true

module Cclikesh
  class CtxProxy
    Blueprint = Struct.new(:main_ractor, :state_refs)

    def self.blueprint(main_ractor, state_refs)
      Ractor.make_shareable(Blueprint.new(main_ractor, state_refs.freeze))
    end

    def self.from_blueprint(bp)
      new(bp.main_ractor, bp.state_refs)
    end

    def initialize(main_ractor, state_refs)
      @main       = main_ractor
      @state_refs = state_refs
      @display    = DisplayProxy.new(@main)
      @logger     = LoggerProxy.new(@main)
      @state      = StateProxy.new(@main)
    end

    attr_reader :display, :logger, :state

    def shareable(name)
      @state_refs[name.to_sym] or raise "no shareable_ref named :#{name}"
    end

    def quit
      @main.send([:quit])
    end

    # ------------------------------------------------------------------
    class DisplayProxy
      def initialize(main)
        @main = main
      end

      def append(text, prompt: nil, style: nil)
        opts = {}
        opts[:prompt] = prompt unless prompt.nil?
        opts[:style]  = style  unless style.nil?
        @main.send([:append, text.to_s.freeze, opts.freeze])
      end

      def open_live(style: nil)
        opts = {}
        opts[:style] = style unless style.nil?
        @main.send([:open_live_request, Ractor.current, opts.freeze])
        msg = Ractor.receive
        # Expect [:open_live_reply, sid]
        sid  = msg[1]
        slot = LiveSlot.new(@main, sid)
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
        opts = {}
        opts[:style] = style unless style.nil?
        @main.send([:dialog, content.to_s.freeze, opts.freeze])
      end
    end

    # ------------------------------------------------------------------
    class LiveSlot
      def initialize(main, sid)
        @main      = main
        @sid       = sid
        @committed = false
      end

      def update(text)
        @main.send([:live_update, @sid, text.to_s.freeze])
      end

      def commit(final = nil)
        final_frozen = final.nil? ? nil : final.to_s.freeze
        @main.send([:live_commit, @sid, final_frozen])
        @committed = true
      end

      def discard
        @main.send([:live_discard, @sid])
        @committed = true
      end

      def committed?
        @committed
      end
    end

    # ------------------------------------------------------------------
    class LoggerProxy
      def initialize(main)
        @main = main
      end

      def debug(msg) = @main.send([:logger, :debug, msg.to_s.freeze])
      def info(msg)  = @main.send([:logger, :info,  msg.to_s.freeze])
      def warn(msg)  = @main.send([:logger, :warn,  msg.to_s.freeze])
      def error(msg) = @main.send([:logger, :error, msg.to_s.freeze])
      def fatal(msg) = @main.send([:logger, :fatal, msg.to_s.freeze])
    end

    # ------------------------------------------------------------------
    class StateProxy
      def initialize(main)
        @main = main
      end

      def []=(key, value)
        frozen = value.frozen? ? value : (value.dup.freeze rescue value)
        @main.send([:state_set, key.to_sym, frozen])
      end

      def [](key)
        @main.send([:state_get_request, Ractor.current, key.to_sym])
        msg = Ractor.receive
        # Expect [:state_get_reply, value]
        msg[1]
      end
    end
  end
end
