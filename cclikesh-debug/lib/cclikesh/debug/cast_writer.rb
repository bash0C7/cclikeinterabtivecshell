require "json"

module Cclikesh
  module Debug
    module CastWriter
      def self.write(io, frames:, rows:, cols:, started_at:)
        io.write({ version: 2, width: cols, height: rows, timestamp: started_at }.to_json + "\n")
        frames.each do |f|
          bytes = f[:raw_bytes].to_s
          next if bytes.empty?
          io.write([f[:ts], "o", bytes].to_json + "\n")
        end
      end
    end
  end
end
