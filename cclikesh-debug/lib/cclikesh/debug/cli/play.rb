require_relative "../spec_dsl"

module Cclikesh
  module Debug
    module CLI
      module Play
        def self.call(argv:, stdout:)
          opts =
            begin
              parse(argv)
            rescue ArgumentError => e
              stdout.puts "spec error: #{e.message}"
              return 3
            end
          src =
            begin
              File.read(opts.fetch(:spec_path))
            rescue Errno::ENOENT => e
              stdout.puts "spec error: #{e.message}"
              return 3
            end
          result =
            begin
              SpecDSL.evaluate(src, db_path: opts.fetch(:db_path),
                                    spec_path: opts.fetch(:spec_path))
            rescue SpecDSL::DslError => e
              stdout.puts "spec error: #{e.message}"
              return 3
            end

          outcomes = SpecDSL.dispatch_expects(result)
          outcomes.each do |o|
            verb = o[:pass] ? "PASS" : "FAIL"
            line = "#{verb}: #{o[:label]}"
            line += " (#{o[:error].class}: #{o[:error].message})" if o[:error]
            stdout.puts line
          end

          duration = result.captured.frames.empty? ? 0.0 : result.captured.frames.last[:ts]
          stdout.puts(format(
            "session %s recorded (%d events, %.2fs)",
            result.session_uuid, result.captured.frames.size, duration
          ))

          return 2 if result.exit_status.nil?
          outcomes.any? { |o| !o[:pass] } ? 1 : 0
        end

        def self.parse(argv)
          opts = { spec_path: nil, db_path: default_db_path }
          i = 0
          while i < argv.length
            case argv[i]
            when "--db"
              opts[:db_path] = argv[i + 1]; i += 2
            else
              opts[:spec_path] = argv[i]; i += 1
            end
          end
          raise ArgumentError, "play: missing <spec.rb>" if opts[:spec_path].nil?
          opts
        end

        def self.default_db_path
          longrun = File.join(Dir.pwd, "tmp", "longrun")
          dir = File.directory?(longrun) ? longrun : Dir.pwd
          File.join(dir, "cclikesh-debug.sqlite")
        end
      end
    end
  end
end
