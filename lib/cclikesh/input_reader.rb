# frozen_string_literal: true

module Cclikesh
  class InputReader
    def initialize(tuple_space, input_io)
      @ts = tuple_space
      @in = input_io
    end

    def read_one
      line = @in.gets
      payload = line.nil? ? nil : line.chomp
      @ts.write([:key, payload])
    end
  end
end
