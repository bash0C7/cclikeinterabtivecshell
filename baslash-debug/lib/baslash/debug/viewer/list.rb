module Baslash
  module Debug
    module Viewer
      module List
        def self.call(_argv)
          out_dir = ENV["BASLASH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "baslash-debug")
          return puts "no sessions in #{out_dir}" unless Dir.exist?(out_dir)
          Dir.glob(File.join(out_dir, "*.sqlite")).sort.each do |path|
            base = File.basename(path, ".sqlite")
            short = base.split("-").last
            sock_path = File.join(File.dirname(path), "#{short}.sock")
            live = File.exist?(sock_path)
            puts "#{live ? '*' : ' '}\t#{File.basename(path)}\t#{path}"
          end
        end
      end
    end
  end
end
