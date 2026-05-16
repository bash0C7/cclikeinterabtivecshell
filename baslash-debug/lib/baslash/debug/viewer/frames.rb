require_relative "../storage"
require_relative "info"

module Baslash
  module Debug
    module Viewer
      module Frames
        def self.call(argv)
          session = argv.shift or abort("usage: baslash-debug frames <session>")
          storage = Baslash::Debug::Storage.open(Baslash::Debug::Viewer::Info.resolve_db(session), readonly: true)
          rows = storage.select_frames(limit: 1000)
          rows.each do |r|
            puts "#{r[:id]}\t#{r[:ts]}\t#{r[:trigger]}\t#{r[:event_kind] || '-'}\t#{r[:content][0, 80]}"
          end
        end
      end
    end
  end
end
