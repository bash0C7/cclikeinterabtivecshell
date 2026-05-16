# frozen_string_literal: true

require "timeout"
require_relative "title_bar"

module Baslash
  # Drives TitleBar spinner during synchronous handler execution.
  # Reline's periodic_tick_proc is dormant while a handler runs on the
  # main thread, so we spawn a background Ractor that emits OSC 0
  # spinner frames every ~120ms to keep the visible spinner alive.
  # Stopped synchronously when the handler returns.
  #
  # NOTE: this module does not use Thread.new (codebase ban). Ractors
  # are the only available concurrency primitive. The Ractor writes
  # OSC 0 escapes directly to $stdout because TitleBar's module state
  # lives in the main Ractor and is not reachable from other Ractors.
  # We update TitleBar.last_phase on start/stop (main-Ractor calls)
  # so tests and external observers see the phase transitions.
  module WorkingIndicator
    TICK_INTERVAL_S = 0.12
    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    @ractor = nil

    class << self
      def start(ctx_text_provider: nil)
        return if @ractor
        # Snapshot ctx_text at start (Ractor cannot call back into main
        # Ractor). For v1 we don't refresh ctx text per tick; the title
        # spinner glyph changing is enough to convey "still working".
        ctx_text = if ctx_text_provider
          begin
            ctx_text_provider.call.to_s
          rescue StandardError
            ""
          end
        else
          ""
        end
        ctx_text = ctx_text.frozen? ? ctx_text : ctx_text.dup.freeze

        # Mark main-Ractor TitleBar phase as :working so observers see it.
        Baslash::TitleBar.tick(phase: :working, ctx_text: ctx_text)

        @ractor = Ractor.new(ctx_text, TICK_INTERVAL_S, SPINNER_FRAMES) do |text, interval, frames|
          frame = 0
          loop do
            begin
              msg = Timeout.timeout(interval) { Ractor.receive }
              break if msg == :stop
            rescue Timeout::Error
              glyph = frames[frame % frames.size]
              frame += 1
              line = text.empty? ? glyph : "#{glyph} #{text}"
              $stdout.print("\e]0;#{line}\a")
              $stdout.flush
            end
          end
        end
      end

      def stop
        r = @ractor
        @ractor = nil
        return unless r
        begin
          r.send(:stop)
        rescue StandardError
          # Ractor may already be closed; nothing actionable here.
          nil
        end
        begin
          r.join
        rescue StandardError
          # Join may raise if the Ractor errored; we still want to
          # restore :ready phase below.
          nil
        end
        Baslash::TitleBar.tick(phase: :ready, ctx_text: "")
      end
    end
  end
end
