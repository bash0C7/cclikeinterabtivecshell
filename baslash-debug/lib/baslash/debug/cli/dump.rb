require_relative "../dump"
require_relative "play"

module Baslash
  module Debug
    module CLI
      module Dump
        def self.call(argv:, stdout:)
          opts = parse(argv)
          Baslash::Debug::Dump.to_io(
            db_path: opts[:db_path],
            session_uuid: opts[:session_uuid],
            io: stdout,
            io_filter: opts[:io_filter]
          )
          0
        end

        def self.parse(argv)
          opts = { session_uuid: nil, db_path: CLI::Play.default_db_path, io_filter: "both" }
          i = 0
          while i < argv.length
            case argv[i]
            when "--db" then opts[:db_path]   = argv[i + 1]; i += 2
            when "--io" then opts[:io_filter] = argv[i + 1]; i += 2
            else             opts[:session_uuid] = argv[i];  i += 1
            end
          end
          raise ArgumentError, "dump: missing <session_uuid>" if opts[:session_uuid].nil?
          opts
        end
      end
    end
  end
end
