require "json"
require_relative "term_sim"

module Cclikesh
  module Debug
    class Captured
      def self.from_storage(storage, uuid, diag_entries: [])
        info = storage.fetch_session(uuid)
        frames = storage.each_event(uuid).to_a
        new(uuid: uuid, info: info, frames: frames, diag_entries: diag_entries)
      end

      def initialize(uuid:, info:, frames:, diag_entries: [])
        @uuid          = uuid
        @info          = info
        @frames        = frames.freeze
        @diag_entries  = diag_entries.freeze
        # Eager pre-compute every memoized field so that the instance can be
        # safely frozen below. Lazy ||= would mutate ivars after freeze and
        # raise FrozenError on first access.
        @output_bytes      = @frames.select { |f| f[:dir] == "o" }
                                    .map { |f| f[:bytes] }.join.b.freeze
        @input_log         = @frames.select { |f| f[:dir] == "i" }
                                    .map { |f| f[:bytes] }.join.b.freeze
        @output_text       = @output_bytes.dup.force_encoding(Encoding::UTF_8).scrub.freeze
        @output_text_clean = @output_text
                               .gsub(/\e\[[0-9;]*[A-Za-z]/, "")     # CSI (SGR, cursor, etc.)
                               .gsub(/\e[78]/, "")                  # DECSC / DECRC
                               .gsub(/\e\].*?(?:\a|\e\\)/m, "")     # OSC (zsh/claude title, hyperlinks)
                               .freeze
        freeze
      end

      attr_reader :frames, :diag_entries

      def session_uuid; @uuid; end
      def exit_status;  @info[:exit_status]; end
      def spawn_cols;   @info[:cols]; end
      def spawn_rows;   @info[:rows]; end

      def output_bytes;      @output_bytes;      end
      def input_log;         @input_log;         end
      def output_text;       @output_text;       end
      def output_text_clean; @output_text_clean; end

      def contains?(substring); @output_bytes.include?(substring.b); end
      def match?(regex);        regex.match?(@output_text);          end

      # Render the captured output stream through a minimal terminal emulator
      # at (rows, cols) and return the resulting TermSim. Use for spec
      # assertions that need to know the *visible* row/col layout (rather
      # than just the byte stream — the byte stream often contains DECSC/
      # DECRC bracketed motion that does not produce a visible gap).
      def screen(rows:, cols:)
        sim = TermSim.new(rows, cols)
        sim.feed(@output_bytes)
        sim
      end
    end
  end
end
