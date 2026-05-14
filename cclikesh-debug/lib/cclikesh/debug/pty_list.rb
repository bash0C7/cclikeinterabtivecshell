require_relative "pty_storage"

module Cclikesh
  module Debug
    module PtyList
      HEADER = "uuid                                  started_at                exit  argv"

      def self.to_io(db_path:, io:)
        storage = PtyStorage.open(db_path)
        begin
          io.puts HEADER
          storage.list_sessions.each do |row|
            io.puts format_row(row)
          end
        ensure
          storage.close
        end
      end

      def self.format_row(row)
        exit_col = row[:exit_status].nil? ? "-" : row[:exit_status].to_s
        format("%-36s  %-24s  %-4s  %s",
               row[:uuid], row[:started_at], exit_col, row[:argv].join(" "))
      end
    end
  end
end
