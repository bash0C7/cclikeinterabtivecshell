require_relative "../storage"
require_relative "info"

module Baslash
  module Debug
    module Viewer
      module Query
        def self.call(argv)
          session = argv.shift or abort("usage: baslash-debug query <session> <SQL>")
          sql = argv.shift or abort("usage: baslash-debug query <session> <SQL>")
          storage = Baslash::Debug::Storage.open(Baslash::Debug::Viewer::Info.resolve_db(session), readonly: true)
          storage.db.query_array(sql).each do |row|
            puts row.join("\t")
          end
        end
      end
    end
  end
end
