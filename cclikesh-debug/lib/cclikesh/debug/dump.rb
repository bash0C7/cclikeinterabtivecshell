require_relative "pty_storage"

module Cclikesh
  module Debug
    module Dump
      def self.to_io(db_path:, session_uuid:, io:, io_filter: "both")
        keep = filter_set(io_filter)
        storage = PtyStorage.open(db_path)
        begin
          storage.each_event(session_uuid) do |e|
            next unless keep.include?(e[:dir])
            io.puts format_line(e)
          end
        ensure
          storage.close
        end
      end

      def self.filter_set(io_filter)
        case io_filter
        when "i"    then %w[i]
        when "o"    then %w[o]
        when "both" then %w[i o x]
        else raise ArgumentError, "io_filter must be one of i / o / both"
        end
      end

      def self.format_line(event)
        bytes = event[:bytes].b
        hex   = bytes.bytes.map { |b| format("%02x", b) }.join(" ")
        ascii = bytes.bytes.map { |b| (0x20..0x7e).cover?(b) ? b.chr : "." }.join
        format("%.3f  %s  %s  |%s|", event[:ts], event[:dir], hex, ascii)
      end
    end
  end
end
