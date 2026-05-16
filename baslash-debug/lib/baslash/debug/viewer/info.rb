require "json"
require_relative "../storage"

module Baslash
  module Debug
    module Viewer
      module Info
        def self.call(argv)
          session = argv.shift or abort("usage: baslash-debug info <session> [--frame N]")
          db = resolve_db(session)
          storage = Baslash::Debug::Storage.open(db, readonly: true)
          info = storage.session_info
          info.each { |k, v| puts "#{k}: #{v}" }
          if (idx = argv.index("--frame"))
            frame_id = Integer(argv[idx + 1])
            row = storage.db.query_single(
              "SELECT ts, trigger, event_kind, framework_state_json FROM frames WHERE id = ?", frame_id
            )
            abort("no frame #{frame_id}") unless row
            puts "---"
            puts "ts: #{row[:ts]}"
            puts "trigger: #{row[:trigger]}"
            puts "event_kind: #{row[:event_kind] || '-'}"
            puts "framework_state:"
            puts JSON.pretty_generate(JSON.parse(row[:framework_state_json]))
          end
        end

        def self.resolve_db(session)
          out_dir = ENV["BASLASH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "baslash-debug")
          matches = Dir.glob(File.join(out_dir, "*#{session}*.sqlite"))
          abort("no session DB matching #{session}") if matches.empty?
          matches.first
        end
      end
    end
  end
end
