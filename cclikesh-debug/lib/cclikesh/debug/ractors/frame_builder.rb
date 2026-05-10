require "json"

module Cclikesh
  module Debug
    module Ractors
      module FrameBuilder
        # Spawns a Ractor that accumulates PTY bytes and emits frame data on capture triggers.
        #
        # DRb-in-Ractor note: DRb relies on shared state (DRb.current_server, DRb::DRbConn cache,
        # etc.) which is inherently un-Ractor-safe. Attempting DRbObject.new_with_uri inside a
        # Ractor raises Ractor::UnsafeError at require time or connection time.
        #
        # Mitigation: orchestrator pulls debug_snapshot via DRb in the main thread/Ractor and
        # sends [:capture_with_snapshot, trigger, event_kind, snapshot_hash] to this Ractor.
        # The [:capture, ...] form is kept for documentation purposes but the snapshot must be
        # pre-fetched and included by the caller.
        def self.spawn(downstream:)
          Ractor.new(downstream) do |down|
            require "json"

            raw_buffer = +"".b
            loop do
              msg = Ractor.receive
              case msg
              in [:bytes, chunk, _ts]
                raw_buffer << chunk
              in [:capture_with_snapshot, trigger, event_kind, snap]
                # snap is a plain Hash (Ractor-shareable since frozen or primitive values)
                framework_state = snap[:framework_state] || {}
                cursor = snap[:cursor] || [0, 0]

                # Build content from framework_state
                content = build_content(framework_state)

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

        # Inline content builder (duplicated from ContentBuilder to avoid require issues in Ractor).
        # Ractors can require files, but only if they don't touch shared mutable state at require time.
        # ContentBuilder is stateless so it should be safe, but inlining avoids any risk.
        def self.build_content(state)
          return "" unless state.is_a?(Hash)

          parts = []
          header = get_key(state, :header) || {}
          parts << get_key(header, :note)

          Array(get_key(state, :info_bar)).each { |i| parts << get_key(i, :text) }

          Array(get_key(state, :status_rows)).each do |r|
            Array(get_key(r, :segments)).each { |s| parts << get_key(s, :text) }
          end

          input = get_key(state, :input) || {}
          parts << get_key(input, :buffer)

          live = get_key(state, :live_slot) || {}
          parts << get_key(live, :text) if get_key(live, :active)

          popup = get_key(state, :popup) || {}
          if get_key(popup, :active)
            kind = get_key(popup, :kind)
            n    = get_key(popup, :candidates_count) || 0
            parts << "popup:#{kind}:#{n}"
          end

          parts.compact.reject { |p| p.respond_to?(:empty?) && p.empty? }.join("\n")
        end

        def self.get_key(hash, key)
          return nil unless hash.is_a?(Hash)
          hash[key.to_sym] || hash[key.to_s]
        end
        private_class_method :build_content, :get_key
      end
    end
  end
end
