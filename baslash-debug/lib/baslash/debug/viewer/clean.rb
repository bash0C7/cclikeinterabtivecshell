module Baslash
  module Debug
    module Viewer
      module Clean
        def self.call(argv)
          out_dir = ENV["BASLASH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "baslash-debug")
          cutoff = if (idx = argv.index("--older-than"))
                     parse_age(argv[idx + 1])
                   else
                     nil
                   end
          Dir.glob(File.join(out_dir, "*.sqlite")).each do |path|
            next if cutoff && File.mtime(path) > cutoff
            File.unlink(path)
            ["#{path}-wal", "#{path}-shm"].each { |aux| File.unlink(aux) if File.exist?(aux) }
            puts "removed: #{path}"
          end
        end

        def self.parse_age(s)
          n, unit = s.match(/(\d+)([dhm])/).captures
          seconds = case unit
                    when "d" then 86400
                    when "h" then 3600
                    when "m" then 60
                    end
          Time.now - Integer(n) * seconds
        end
      end
    end
  end
end
