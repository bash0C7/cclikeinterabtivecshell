require_relative "../storage"
require_relative "input"

module Cclikesh
  module Debug
    module Driver
      module Tail
        def self.call(argv)
          session = argv.shift or abort("usage: cclikesh-debug tail <session>")
          sock = Cclikesh::Debug::Driver::Input.resolve_socket(session)
          db_path = find_db_for_sock(sock, session)
          abort("no DB matching #{session}") unless db_path && File.exist?(db_path)

          storage = Cclikesh::Debug::Storage.open(db_path, readonly: true)
          last_id = 0
          loop do
            rows = storage.db.execute(
              "SELECT id, ts, event_kind, content FROM frames WHERE id > ? ORDER BY id",
              [last_id]
            )
            rows.each do |r|
              puts "#{r[0]}\t#{r[1]}\t#{r[2] || '-'}\t#{r[3].to_s.gsub("\n", " ⏎ ")[0, 200]}"
              last_id = r[0]
            end
            sleep 0.5
          end
        rescue Interrupt
          # clean exit on Ctrl-C
        end

        def self.find_db_for_sock(sock, session)
          out_dir = File.dirname(sock)
          # Sock basename is "<short>.sock"; short is the first 8 chars of the uuid.
          # DB is named "<ts>-<pid>-<short>.sqlite".
          short = File.basename(sock, ".sock")
          matches = Dir.glob(File.join(out_dir, "*#{short}*.sqlite"))
          matches.first
        end
        private_class_method :find_db_for_sock
      end
    end
  end
end
