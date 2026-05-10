require "zlib"
require_relative "../storage"
require_relative "info"

module Cclikesh
  module Debug
    module Viewer
      module Grid
        def self.call(argv)
          session = argv.shift
          idx = argv.index("--frame") or abort("--frame N required")
          frame_id = Integer(argv[idx + 1])
          db = Cclikesh::Debug::Viewer::Info.resolve_db(session)
          storage = Cclikesh::Debug::Storage.open(db, readonly: true)
          row = storage.db.query_single("SELECT raw_bytes_zlib FROM frames WHERE id = ?", frame_id)
          abort("no frame #{frame_id}") unless row
          bytes = row[:raw_bytes_zlib] ? Zlib::Inflate.inflate(row[:raw_bytes_zlib]) : ""
          $stdout.binmode.write(bytes)
        end
      end
    end
  end
end
