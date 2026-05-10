require "zlib"
require "open3"
require_relative "../storage"
require_relative "../cast_writer"
require_relative "info"

module Cclikesh
  module Debug
    module Viewer
      module Export
        def self.call(argv)
          session = argv.shift or abort("usage: cclikesh-debug export <session> --format=cast|gif|mp4|webm [--output PATH]")
          fmt    = parse_str(argv, "--format", "cast")
          output = parse_str(argv, "--output", nil) || "#{session}.#{fmt}"
          storage = Cclikesh::Debug::Storage.open(Cclikesh::Debug::Viewer::Info.resolve_db(session), readonly: true)
          info = storage.session_info
          rows = storage.db.query("SELECT ts, raw_bytes_zlib FROM frames ORDER BY ts")
          frames = rows.map { |r| { ts: r[:ts], raw_bytes: r[:raw_bytes_zlib] ? Zlib::Inflate.inflate(r[:raw_bytes_zlib]) : "" } }

          case fmt
          when "cast"
            File.open(output, "w") do |f|
              Cclikesh::Debug::CastWriter.write(f, frames: frames, rows: info[:rows], cols: info[:cols], started_at: 0)
            end
            puts output
          when "gif"
            cast = "/tmp/cclikesh-export-#{Process.pid}.cast"
            File.open(cast, "w") do |f|
              Cclikesh::Debug::CastWriter.write(f, frames: frames, rows: info[:rows], cols: info[:cols], started_at: 0)
            end
            _, _, st = Open3.capture3("agg", cast, output)
            File.unlink(cast) rescue nil
            abort("agg failed (install: brew install agg)") unless st.success?
            puts output
          when "mp4", "webm"
            cast = "/tmp/cclikesh-export-#{Process.pid}.cast"
            gif  = "/tmp/cclikesh-export-#{Process.pid}.gif"
            File.open(cast, "w") do |f|
              Cclikesh::Debug::CastWriter.write(f, frames: frames, rows: info[:rows], cols: info[:cols], started_at: 0)
            end
            _, _, st = Open3.capture3("agg", cast, gif)
            unless st.success?
              [cast, gif].each { |p| File.unlink(p) rescue nil }
              abort("agg failed (install: brew install agg)")
            end
            _, _, st = Open3.capture3("ffmpeg", "-y", "-i", gif, output)
            [cast, gif].each { |p| File.unlink(p) rescue nil }
            abort("ffmpeg failed (install: brew install ffmpeg)") unless st.success?
            puts output
          else
            abort("unsupported format: #{fmt}")
          end
        end

        def self.parse_str(argv, flag, default)
          flag_with_eq = "#{flag}="
          if (idx = argv.index { |a| a.start_with?(flag_with_eq) })
            argv.delete_at(idx).split("=", 2)[1]
          elsif (idx = argv.index(flag))
            argv.delete_at(idx)
            argv.delete_at(idx)
          else
            default
          end
        end
      end
    end
  end
end
