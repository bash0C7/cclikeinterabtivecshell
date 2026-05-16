# frozen_string_literal: true

module Baslash
  # Sets the terminal window title via OSC 0 escape sequences. Used to
  # surface ephemeral status (phase, cwd, var count, spinner) without
  # consuming on-screen real estate. macOS Terminal.app honors OSC 0;
  # cmux passes the sequence through transparently.
  module TitleBar
    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
    READY_GLYPH    = "✻"

    @frame      = 0
    @tick_count = 0
    @last_phase = :ready

    class << self
      attr_reader :tick_count
      attr_reader :last_phase

      def set(text)
        safe = text.to_s.gsub(/[\a\e]/, "")
        $stdout.print("\e]0;#{safe}\a")
        $stdout.flush
      end

      def restore
        $stdout.print("\e]0;\a")
        $stdout.flush
      end

      def tick(phase:, ctx_text:)
        @tick_count += 1
        @last_phase = phase
        glyph = phase == :working ? next_spinner_frame : READY_GLYPH
        text = ctx_text.to_s.empty? ? glyph : "#{glyph} #{ctx_text}"
        set(text)
      end

      def reset_for_test
        @frame      = 0
        @tick_count = 0
        @last_phase = :ready
      end

      private

      def next_spinner_frame
        f = SPINNER_FRAMES[@frame % SPINNER_FRAMES.size]
        @frame += 1
        f
      end
    end
  end
end
