require_relative "../replay"
require_relative "play"

module Cclikesh
  module Debug
    module CLI
      module Replay
        def self.call(argv:, stdout:)
          opts = parse(argv)
          Cclikesh::Debug::Replay.to_io(
            db_path: opts[:db_path],
            session_uuid: opts[:session_uuid],
            io: stdout,
            speed: opts[:speed]
          )
          0
        end

        def self.parse(argv)
          opts = { session_uuid: nil, db_path: CLI::Play.default_db_path, speed: 1.0 }
          i = 0
          while i < argv.length
            case argv[i]
            when "--db"    then opts[:db_path] = argv[i + 1];          i += 2
            when "--speed" then opts[:speed]   = Float(argv[i + 1]);   i += 2
            else                opts[:session_uuid] = argv[i];          i += 1
            end
          end
          raise ArgumentError, "replay: missing <session_uuid>" if opts[:session_uuid].nil?
          opts
        end
      end
    end
  end
end
