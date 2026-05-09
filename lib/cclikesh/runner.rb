# frozen_string_literal: true

require "drb/drb"
require "drb/unix"
require_relative "drb_patches"
require "reline"
require_relative "tuple_space"
require_relative "builder"
require_relative "context"
require_relative "dispatcher"
require_relative "handler_registry"
require_relative "forking"
require_relative "render_thread"
require_relative "input_thread"
require_relative "event_thread"
require_relative "screen"
require_relative "layout"
require_relative "header"
require_relative "history"

module Cclikesh
  class Runner
    def self.run(tick_interval: 0.06, &block)
      builder = Builder.new
      block.call(builder)
      registry = HandlerRegistry.new(builder)

      Forking.run(registry) do |handlers_uri|
        run_child(handlers_uri, tick_interval: tick_interval)
      end
    end

    def self.run_child(handlers_uri, tick_interval: nil)
      Screen.enter_alt
      Layout.update_from_io($stdout)
      @history_path = History.path_for(Dir.pwd)
      History.load(@history_path).each { |entry| Reline::HISTORY << entry }
      DRb.start_service
      registry_remote = DRbObject.new_with_uri(handlers_uri)

      effective_tick = tick_interval || registry_remote.tick_interval

      Layout.recompute(
        header_height: registry_remote.header_height,
        footer_height: registry_remote.footer_height
      )
      Header.paint($stdout, registry_remote.header_lines) if $stdout.tty?
      Layout.set_scroll_region($stdout) if $stdout.tty?

      @registry_for_winch = registry_remote
      install_winch_trap

      ts = TupleSpace.new
      ctx = Context.new(ts, registry: registry_remote)
      dispatcher = Dispatcher.new(ts, registry_remote, ctx)

      @ts_for_winch = ts

      render_thread = RenderThread.start(ts, $stdout,
                                         tick_interval: effective_tick,
                                         registry: registry_remote,
                                         ctx: ctx)
      input_thread  = InputThread.start(ts, reader: multiline_reader, prompt: "> ",
                                        registry: registry_remote, ctx: ctx)
      event_thread  = EventThread.start(ts, registry: registry_remote, ctx: ctx)

      registry_remote.dispatch_start(ctx)

      loop do
        break if dispatcher.dispatch_one == :quit
      end

      registry_remote.dispatch_quit(ctx)

      # Give EventThread 2 ticks (tick=0.05s) to drain any state_change events
      # emitted during dispatch_quit before signaling thread shutdown.
      sleep 0.1

      ts.write([:cmd, :quit])
      render_thread.join(2)
      input_thread.join(2)
      event_thread.join(2)
      DRb.stop_service
    ensure
      History.save(@history_path, Reline::HISTORY.to_a) if @history_path
      Layout.reset_scroll_region($stdout) if $stdout.tty?
      Screen.leave_alt
    end

    def self.multiline_reader
      lambda do |prompt|
        Reline.readmultiline(prompt, true) do |whole|
          last = whole.lines.last || whole
          !last.chomp.end_with?("\\")
        end
      end
    end

    def self.install_winch_trap
      return unless $stdout.tty?
      Signal.trap("WINCH") do
        Layout.update_from_io($stdout)
        Header.paint($stdout, @registry_for_winch.header_lines) if @registry_for_winch
        Layout.set_scroll_region($stdout)
        @ts_for_winch&.write([:cmd, :refresh])
      end
    rescue ArgumentError
      # SIGWINCH not supported on this platform
    end
  end
end
