# frozen_string_literal: true

module Cclikesh
  module DebugEndpoint
    class << self
      attr_reader :adapter
    end

    def self.start_if_enabled(builder)
      sock = ENV["CCLIKESH_DEBUG_SOCK"]
      return nil unless sock
      require "drb/drb"
      @adapter = Adapter.new(builder)
      @service = DRb.start_service("drbunix:#{sock}.drb", @adapter)
      @adapter
    end

    def self.stop_for_test
      @service&.stop_service rescue nil
      @adapter = nil
      @service = nil
    end

    class Adapter
      def initialize(builder)
        @builder = builder
        @mutex = Mutex.new
        @events = []
      end

      def debug_snapshot
        @mutex.synchronize do
          {
            framework_state: build_framework_state_hash,
            cursor:          current_cursor,
            ts_shell:        Process.clock_gettime(Process::CLOCK_MONOTONIC)
          }
        end
      end

      def debug_drain_events
        @mutex.synchronize do
          drained = @events.dup
          @events.clear
          drained
        end
      end

      def push_event(kind, payload = {})
        @mutex.synchronize do
          @events << { kind: kind, payload: payload, ts: Time.now.to_f }
        end
      end

      private

      def build_framework_state_hash
        require_relative "context"
        require_relative "transcript"
        main_ctx = Cclikesh::MainCtx.new(@builder.state_refs)
        {
          phase:             Cclikesh::Context.state[:phase],
          focus_mode:        Cclikesh::Context.state[:focus_mode],
          header:            @builder.header_config,
          info_bar:          @builder.evaluate_info_bar(main_ctx),
          status_rows:       @builder.evaluate_status_rows(main_ctx),
          spinner_label:     @builder.evaluate_spinner_label,
          prompt_suggestion: @builder.evaluate_prompt_suggestion,
          shortcuts_hint:    @builder.shortcuts_hint_text,
          input:             reline_input_state,
          live_slot:         live_slot_state,
          popup:             popup_state,
          transcript_line_count: Cclikesh::Transcript.lines.size
        }
      end

      def reline_input_state
        require "reline"
        { buffer: Reline.line_buffer.to_s, cursor_pos: Reline.point.to_i }
      rescue
        { buffer: "", cursor_pos: 0 }
      end

      def live_slot_state
        require_relative "display"
        slots = (Cclikesh::Display.respond_to?(:live_slot_state) ? Cclikesh::Display.live_slot_state : {}) rescue {}
        return { active: false, text: nil, style: nil } if slots.nil? || slots.empty?
        first = slots.values.first
        { active: true, text: first[:last_text], style: first[:style] }
      end

      def popup_state
        # v1: no popup state introspection. RelineDialogs has no public popup state accessor.
        { active: false, kind: nil, candidates_count: 0, selection_index: 0 }
      end

      def current_cursor
        require "curses"
        [Curses.stdscr.cury, Curses.stdscr.curx]
      rescue
        [0, 0]
      end
    end
  end
end
