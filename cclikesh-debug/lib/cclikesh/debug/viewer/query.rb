require_relative "../storage"
require_relative "info"

module Cclikesh
  module Debug
    module Viewer
      module Query
        def self.call(argv)
          session = argv.shift or abort("usage: cclikesh-debug query <session> <SQL>")
          sql = argv.shift or abort("usage: cclikesh-debug query <session> <SQL>")
          storage = Cclikesh::Debug::Storage.open(Cclikesh::Debug::Viewer::Info.resolve_db(session), readonly: true)
          storage.db.query_array(sql).each do |row|
            puts row.join("\t")
          end
        end
      end
    end
  end
end
