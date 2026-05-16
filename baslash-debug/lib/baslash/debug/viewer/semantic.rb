require_relative "../storage"
require_relative "../embedder_pool"
require_relative "info"

module Baslash
  module Debug
    module Viewer
      module Semantic
        def self.call(argv)
          session = argv.shift or abort("usage: baslash-debug semantic <session> <query> [-k N]")
          query = argv.shift   or abort("usage: baslash-debug semantic <session> <query> [-k N]")
          k = (idx = argv.index("-k")) ? Integer(argv[idx + 1]) : 5
          storage = Baslash::Debug::Storage.open(Baslash::Debug::Viewer::Info.resolve_db(session), readonly: true)
          pool = Baslash::Debug::EmbedderPool.new
          vec = pool.embed(query)
          blob = vec.pack("f*")
          rows = storage.db.query(
            "SELECT v.frame_id, v.distance, f.ts, f.content
               FROM frame_vec v JOIN frames f ON f.id = v.frame_id
              WHERE v.embedding MATCH ? AND k = ?
              ORDER BY v.distance",
            blob, k
          )
          rows.each { |r| puts "#{r[:frame_id]}\t#{r[:distance].round(3)}\t#{r[:ts]}\t#{r[:content][0, 60]}" }
        end
      end
    end
  end
end
