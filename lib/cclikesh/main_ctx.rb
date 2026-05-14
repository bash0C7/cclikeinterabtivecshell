# frozen_string_literal: true

module Cclikesh
  # Read-only context passed to status_row / info blocks during footer redraw.
  # These blocks run on the main Ractor, not inside a handler Ractor,
  # so they get a subset of CtxProxy's surface: shareable_ref lookup and state read.
  class MainCtx
    def initialize(state_refs)
      @state_refs = state_refs
      @state      = ReadOnlyState.new
    end

    def shareable(name)
      @state_refs[name.to_sym] or raise "no shareable_ref named :#{name}"
    end

    attr_reader :state

    class ReadOnlyState
      def [](key)
        Cclikesh::Context.state[key.to_sym]
      end
    end
  end
end
