module Baslash
  module Debug
    module Driver
      module Wait
        def self.call(argv)
          _session = argv.shift or abort("usage: baslash-debug wait <session> --idle <ms>")
          idx = argv.index("--idle")
          abort("--idle <ms> required") unless idx
          idle_ms = Integer(argv[idx + 1])
          sleep idle_ms / 1000.0
        end
      end
    end
  end
end
