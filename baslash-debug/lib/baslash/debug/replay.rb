require_relative "pty_storage"

module Baslash
  module Debug
    module Replay
      def self.to_io(db_path:, session_uuid:, io:, speed: 1.0)
        storage = PtyStorage.open(db_path)
        begin
          prev_ts = nil
          storage.each_event(session_uuid) do |e|
            next unless e[:dir] == "o"
            if prev_ts && speed > 0
              delta = (e[:ts] - prev_ts) / speed
              sleep(delta) if delta > 0
            end
            io.write(e[:bytes])
            io.flush
            prev_ts = e[:ts]
          end
        ensure
          storage.close
        end
      end
    end
  end
end
