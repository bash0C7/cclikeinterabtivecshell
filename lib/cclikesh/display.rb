# frozen_string_literal: true

module Cclikesh
  class Display
    def initialize(tuple_space)
      @ts = tuple_space
    end

    def append(text, style: nil, prompt: nil)
      opts = {}
      opts[:style] = style if style
      opts[:prompt] = prompt if prompt
      @ts.write([:render, :display_append, text, opts])
    end
  end
end
