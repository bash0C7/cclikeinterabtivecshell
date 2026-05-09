# frozen_string_literal: true

module Cclikesh
  class InputRactor
    def self.start(ts, input_path)
      Ractor.new(ts, input_path) do |ts, input_path|
        File.open(input_path, "r") do |input|
          loop do
            line = input.gets
            payload = line.nil? ? nil : line.chomp
            ts.write([:key, payload])
            break if payload.nil?
          end
        end
      end
    end
  end
end
