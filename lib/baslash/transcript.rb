# frozen_string_literal: true

module Baslash
  # Minimal stub. Task 5 will replace this with the full port from
  # lib/cclikesh/transcript.rb (ring buffer, redraw hooks, etc.).
  module Transcript
    @lines = []

    class << self
      def record(line)
        @lines << line.to_s
      end

      def lines
        @lines.dup.freeze
      end

      def reset_for_test
        @lines = []
      end
    end
  end
end
