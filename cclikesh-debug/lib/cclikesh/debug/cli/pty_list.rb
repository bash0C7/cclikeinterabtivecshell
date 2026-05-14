require_relative "../pty_list"
require_relative "play"

module Cclikesh
  module Debug
    module CLI
      module PtyList
        def self.call(argv:, stdout:)
          opts = parse(argv)
          Cclikesh::Debug::PtyList.to_io(db_path: opts[:db_path], io: stdout)
          0
        end

        def self.parse(argv)
          opts = { db_path: CLI::Play.default_db_path }
          i = 0
          while i < argv.length
            case argv[i]
            when "--db" then opts[:db_path] = argv[i + 1]; i += 2
            else            i += 1
            end
          end
          opts
        end
      end
    end
  end
end
