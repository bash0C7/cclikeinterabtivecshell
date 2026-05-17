# frozen_string_literal: true

module Baslash
  # Read-only context passed to status_row / info / prompt_prefix blocks
  # during footer redraw. These blocks run on the main thread (Reline
  # loop), so they get a subset of SyncCtx's surface: state read only.
  class MainCtx
    def initialize
      @state = ReadOnlyState.new
    end

    attr_reader :state

    class ReadOnlyState
      def [](key)
        Baslash::Context.state[key.to_sym]
      end
    end
  end
end
