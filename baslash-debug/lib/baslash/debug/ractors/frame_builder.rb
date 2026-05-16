require "json"

module Baslash
  module Debug
    module Ractors
      module FrameBuilder
        # Spawns a Ractor that accumulates PTY bytes and emits frame data on capture triggers.
        #
        # Orchestrator (main Ractor) pulls debug_snapshot via DRb and sends
        # [:capture_with_snapshot, trigger, event_kind, snapshot_hash] here. The snapshot
        # must be deep-frozen by the caller (see Recorder#deep_freeze).
        def self.spawn(downstream:)
          Ractor.new(downstream) do |down|
            require "json"

            # Inline content builder. Defined as a lambda so it is callable from inside
            # the Ractor block without referring to the outer module (which would resolve
            # to the Ractor instance at runtime and raise NoMethodError).
            get_key = ->(hash, key) {
              next nil unless hash.is_a?(Hash)
              hash[key.to_sym] || hash[key.to_s]
            }

            build_content = ->(state) {
              next "" unless state.is_a?(Hash)
              parts = []
              header = get_key.(state, :header) || {}
              parts << get_key.(header, :note)
              Array(get_key.(state, :info_bar)).each { |i| parts << get_key.(i, :text) }
              Array(get_key.(state, :status_rows)).each do |r|
                Array(get_key.(r, :segments)).each { |s| parts << get_key.(s, :text) }
              end
              input = get_key.(state, :input) || {}
              parts << get_key.(input, :buffer)
              live = get_key.(state, :live_slot) || {}
              parts << get_key.(live, :text) if get_key.(live, :active)
              popup = get_key.(state, :popup) || {}
              if get_key.(popup, :active)
                kind = get_key.(popup, :kind)
                n    = get_key.(popup, :candidates_count) || 0
                parts << "popup:#{kind}:#{n}"
              end
              parts.compact.reject { |p| p.respond_to?(:empty?) && p.empty? }.join("\n")
            }

            raw_buffer = +"".b
            loop do
              msg = Ractor.receive
              case msg
              in [:bytes, chunk, _ts]
                raw_buffer << chunk
              in [:capture_with_snapshot, trigger, event_kind, snap]
                framework_state = snap[:framework_state] || {}
                cursor = snap[:cursor] || [0, 0]
                content = build_content.(framework_state)

                down.send([:frame, {
                  ts:                   snap[:ts_shell] || Process.clock_gettime(Process::CLOCK_MONOTONIC),
                  trigger:              trigger.to_s,
                  event_kind:           event_kind,
                  cursor_row:           cursor[0],
                  cursor_col:           cursor[1],
                  raw_bytes:            raw_buffer.dup.freeze,
                  framework_state_json: framework_state.to_json,
                  content:              content
                }.freeze])
                raw_buffer.clear
              in [:eof]
                down.send([:eof])
                break
              in [:stop]
                down.send([:stop])
                break
              else
                # ignore unknown messages
              end
            end
          end
        end
      end
    end
  end
end
